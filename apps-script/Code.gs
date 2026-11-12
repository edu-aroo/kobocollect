/* ============================================================================
   Code.gs — Google Apps Script "backend" of the KoboToolbox course (same engine as the R course)
   ----------------------------------------------------------------------------
   Reads and writes the Google Sheet. Tabs (created by setup()):
     students     : username | password | full_name | active | level | role | email | facebook | phone | open_pages  (YOU fill this)
     progress     : username | full_name | last_page | last_section | updated | state_json
     scores       : timestamp | username | full_name | quiz | page | score | max | answers | attempt
     certificates : code | date | username | full_name | level | score_pct
     alerts       : date | username | full_name | level | page | score_pct | email | facebook | phone
     dashboard    : rebuilt by refreshDashboard() (every day, or by hand)
   Column ORDER does not matter: columns are found by their header name.
   level : empty or "beginner" = beginner; "intermediate" / "advanced" = direct access
   role  : empty or "student"; "teacher" = sees everything, nothing recorded
   open_pages : sessions you open by hand, separated by commas, e.g. "03-multilingual" or
                "03-multilingual, i02-constraint" (file names without .html). Two uses:
                - unblock a stuck student (write the NEXT session);
                - let a student skip lessons they already know (write the session they
                  start from): the earlier sessions they did not attempt are "skipped"
                  and do not count in the level's 75 %.
   E-MAILS you receive: a student stuck below 75 % on a session (once per session),
                        and a student who passes a level (with the certificate code).

   INSTALL / UPDATE: paste this file, save, run setup() once, run installTriggers()
   once, then Deploy > Manage deployments > Edit > Version: New version > Deploy.
   ============================================================================ */

// ---- SETTINGS ----------------------------------------------------------------
// Address of your course site, WITH the final slash. Used to read the list of
// quizzes (assets/quiz_index.json) to check level scores. Leave "" to skip checks.
const SITE_URL = "https://edu-aroo.github.io/kobocollect/";                         // e.g. ""
const ALERT_EMAIL = "aroofalinirina@gmail.com";   // receives "needs help" and "level passed" e-mails
const MAX_ATTEMPTS = 2;                      // same value as maxAttempts in config.js
const PASS = 0.75;                           // same value as passThreshold in config.js
const LEVELS = ["beginner", "intermediate", "advanced"];
const BACKUP_FOLDER = "Kobo course backups";    // Drive folder for the weekly copies

// ---- Tabs and their columns --------------------------------------------------
const TABS = {
  students:     ["username", "password", "full_name", "active", "level", "role", "email", "facebook", "phone", "open_pages"],
  progress:     ["username", "full_name", "last_page", "last_section", "updated", "state_json"],
  scores:       ["timestamp", "username", "full_name", "quiz", "page", "score", "max", "answers", "attempt"],
  certificates: ["code", "date", "username", "full_name", "level", "score_pct"],
  alerts:       ["date", "username", "full_name", "level", "page", "score_pct", "email", "facebook", "phone"]
};

// Run ONCE (and again after an update): creates missing tabs and missing columns.
// Existing rows are never deleted.
function setup() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  Object.keys(TABS).forEach(function (name) {
    let sh = ss.getSheetByName(name) || ss.insertSheet(name);
    const want = TABS[name];
    const have = sh.getLastRow() > 0 ? sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String) : [];
    want.forEach(function (col) {
      if (have.indexOf(col) === -1) { sh.getRange(1, have.length + 1).setValue(col); have.push(col); }
    });
    sh.getRange(1, 1, 1, have.length).setFontWeight("bold");
    sh.setFrozenRows(1);
  });
  if (!ss.getSheetByName("dashboard")) ss.insertSheet("dashboard");
  const st = sheet("students");
  if (st.getLastRow() === 1) addRow("students", { username: "test01", password: "kobo2026",
    full_name: "Test Student", active: "yes", level: "beginner", role: "student" });
}

// Run ONCE: weekly backup (Monday ~2 am) and daily dashboard refresh (~6 am)
function installTriggers() {
  ScriptApp.getProjectTriggers().forEach(function (tr) {
    if (["weeklyBackup", "refreshDashboard"].indexOf(tr.getHandlerFunction()) !== -1) ScriptApp.deleteTrigger(tr);
  });
  ScriptApp.newTrigger("weeklyBackup").timeBased().onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(2).create();
  ScriptApp.newTrigger("refreshDashboard").timeBased().everyDays(1).atHour(6).create();
}

// ---- Every request from the website arrives here --------------------------------
function doPost(e) {
  let req;
  try { req = JSON.parse(e.postData.contents); }
  catch (err) { return out({ ok: false, error: "bad_request" }); }

  const student = checkLogin(req.user, req.pass);
  if (!student) return out({ ok: false, error: "bad_login" });

  const lock = LockService.getScriptLock();     // one request at a time in the sheet
  lock.waitLock(10000);
  try {
    if (req.action === "login")  return out({ ok: true, name: student.full_name, level: student.level,
                                              role: student.role, openPages: student.openPages,
                                              state: readState(student.username) });
    if (req.action === "save")   { writeState(student, req.state); return out({ ok: true }); }
    if (student.role === "teacher") return out({ ok: true });          // teacher: nothing else recorded
    if (req.action === "score")  { logScore(student, req); return out({ ok: true }); }
    if (req.action === "unlock") return out(unlockLevel(student, req));
    if (req.action === "stuck")  { raiseAlert(student, req); return out({ ok: true }); }
    return out({ ok: false, error: "unknown_action" });
  } finally {
    lock.releaseLock();
  }
}

// Opening the URL in a browser simply shows that the script is alive
function doGet() { return out({ ok: true, message: "Course backend is running (v3.1)" }); }

// ---- Helpers ---------------------------------------------------------------------
function out(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
function sheet(name) { return SpreadsheetApp.getActiveSpreadsheet().getSheetByName(name); }

// All rows of a tab as objects {column_name: value}, plus _row = row number
function rows(name) {
  const sh = sheet(name);
  const v = sh.getDataRange().getValues();
  const head = v[0].map(String);
  return v.slice(1).map(function (r, i) {
    const o = { _row: i + 2 };
    head.forEach(function (h, j) { o[h] = r[j]; });
    return o;
  });
}
// Append a row given as {column_name: value}
function addRow(name, obj) {
  const sh = sheet(name);
  const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String);
  sh.appendRow(head.map(function (h) { return obj[h] !== undefined ? obj[h] : ""; }));
}
function setCell(name, rowNumber, column, value) {
  const sh = sheet(name);
  const head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String);
  sh.getRange(rowNumber, head.indexOf(column) + 1).setValue(value);
}

// Returns the student (row object) if username + password match an active account
function checkLogin(user, pass) {
  if (!user || !pass) return null;
  user = String(user).trim().toLowerCase();
  const s = rows("students").find(function (r) {
    return String(r.username).trim().toLowerCase() === user && String(r.password) === String(pass) &&
           String(r.active || "yes").toLowerCase() !== "no";
  });
  if (!s) return null;
  s.username = user;
  s.full_name = String(s.full_name || user);
  s.level = LEVELS.indexOf(String(s.level).toLowerCase()) !== -1 ? String(s.level).toLowerCase() : "beginner";
  s.role = String(s.role).toLowerCase() === "teacher" ? "teacher" : "student";
  s.openPages = String(s.open_pages || "").split(/[,;\s]+/)               // "05-cleaning, i03-joins"
                  .map(function (x) { return x.trim().replace(/\.html$/, ""); })
                  .filter(function (x) { return x; });
  return s;
}

function readState(user) {
  const r = rows("progress").find(function (x) { return String(x.username).toLowerCase() === user; });
  if (!r) return null;
  try { return JSON.parse(r.state_json); } catch (err) { return null; }
}
function writeState(student, state) {
  const r = rows("progress").find(function (x) { return String(x.username).toLowerCase() === student.username; });
  const vals = { username: student.username, full_name: student.full_name, last_page: state.lastPage || "",
                 last_section: state.lastSection || "", updated: new Date(), state_json: JSON.stringify(state) };
  if (!r) { addRow("progress", vals); return; }
  Object.keys(vals).forEach(function (k) { setCell("progress", r._row, k, vals[k]); });
}

// One row per attempt; attempts beyond MAX_ATTEMPTS are ignored
function logScore(student, req) {
  const n = rows("scores").filter(function (r) {
    return String(r.username).toLowerCase() === student.username && String(r.quiz) === String(req.quiz);
  }).length;
  if (n >= MAX_ATTEMPTS) return;
  addRow("scores", { timestamp: new Date(), username: student.username, full_name: student.full_name,
    quiz: req.quiz, page: req.page, score: req.score, max: req.max,
    answers: JSON.stringify(req.answers), attempt: n + 1 });
}

// ---- Levels --------------------------------------------------------------------
// The list of quizzes of the site (made by R/build_site.R), kept in cache 6 hours
function quizIndex() {
  if (!SITE_URL) return null;
  const cache = CacheService.getScriptCache();
  const hit = cache.get("quiz_index");
  if (hit) return JSON.parse(hit);
  try {
    const txt = UrlFetchApp.fetch(SITE_URL + "assets/quiz_index.json", { muteHttpExceptions: true }).getContentText();
    JSON.parse(txt);
    cache.put("quiz_index", txt, 21600);
    return JSON.parse(txt);
  } catch (err) { return null; }
}

// Score of one level for one student, from the "scores" tab (best attempt of each quiz).
// openPages = sessions the teacher opened by hand (column open_pages). A quiz of a
// session placed BEFORE an opened session of the same level, and never attempted,
// is "skipped" and left out of the 75 % (page order = order of the file names:
// 00-, 01-… / i00-, i01-… / a00-, a01-…, as in config.js).
function levelResult(username, level, idx, allScores, openPages) {
  const mine = allScores.filter(function (r) { return String(r.username).toLowerCase() === username; });
  const opened = (openPages || []).filter(function (op) {
    return Object.keys(idx).some(function (id) { return idx[id].page === op && idx[id].level === level; });
  });
  const ids = Object.keys(idx).filter(function (id) {
    if (idx[id].level !== level) return false;
    const tried = mine.some(function (r) { return String(r.quiz) === id; });
    const skipped = !tried && opened.some(function (op) { return String(idx[id].page) < op; });
    return !skipped;
  });
  let earned = 0, total = 0, possible = 0, done = 0;
  ids.forEach(function (id) {
    const att = mine.filter(function (r) { return String(r.quiz) === id; });
    const max = idx[id].max;
    // If the quiz changed size since the attempt (row max differs from the
    // current quiz index), the score is rescaled: 9/12 becomes 7.5/10.
    const best = att.reduce(function (m, r) {
      const rmax = Number(r.max) || max, sc = Number(r.score) || 0;
      return Math.max(m, rmax === max ? sc : Math.round(10 * sc * max / rmax) / 10);
    }, 0);
    total += max;
    if (att.length) { done++; earned += best; }
    possible += att.length >= MAX_ATTEMPTS ? best : max;
  });
  return { n: ids.length, done: done, pct: total ? earned / total : 0,
           passed: ids.length > 0 && done === ids.length && earned >= PASS * total - 1e-9,
           stuck: ids.length > 0 && possible < PASS * total - 1e-9 };
}

// The website says "I passed level X": we check it in the scores tab (if the
// quiz list is available), raise the level in "students" and issue a certificate.
function unlockLevel(student, req) {
  const idx = quizIndex();
  let pct = Number(req.pct) || 0;
  if (idx) {
    const res = levelResult(student.username, req.passed, idx, rows("scores"), student.openPages);
    if (!res.passed) return { ok: false, error: "not_passed" };
    pct = Math.round(100 * res.pct);
  }
  // raise the level (never lower it)
  if (req.level && LEVELS.indexOf(req.level) > LEVELS.indexOf(student.level)) {
    setCell("students", student._row, "level", req.level);
  }
  // one certificate per student and level
  let cert = rows("certificates").find(function (c) {
    return String(c.username).toLowerCase() === student.username && c.level === req.passed;
  });
  if (!cert) {
    cert = { code: "RMS-" + req.passed.slice(0, 3).toUpperCase() + "-" +
                    Utilities.getUuid().slice(0, 8).toUpperCase(),
             date: Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd"),
             username: student.username, full_name: student.full_name, level: req.passed, score_pct: pct };
    addRow("certificates", cert);
    notifyLevelPassed(student, req.passed, req.level, cert);     // e-mail to the teacher, once
  }
  return { ok: true, level: req.level || student.level,
           certificate: { code: cert.code, date: String(cert.date).slice(0, 10), pct: Number(cert.score_pct) } };
}

// E-mail to the teacher when a student passes a level (sent once, with the certificate)
function notifyLevelPassed(student, passed, next, cert) {
  if (!ALERT_EMAIL) return;
  MailApp.sendEmail(ALERT_EMAIL,
    "[Kobo course] " + student.full_name + " passed the " + passed + " level (" + cert.score_pct + " %)",
    "A student has passed a level of the course.\n\n" +
    "Name:        " + student.full_name + "\n" +
    "Username:    " + student.username + "\n" +
    "Level:       " + passed + " (" + cert.score_pct + " %)\n" +
    "Now open:    " + (next || "-") + "\n" +
    "Certificate: " + cert.code + "\n" +
    "E-mail:      " + (student.email || "-") + "\n" +
    "Facebook:    " + (student.facebook || "-") + "\n" +
    "Phone:       " + (student.phone || "-") + "\n");
}

// The website says "this student cannot reach 75 % on this session any more":
// record + e-mail ONCE per student and session (resetQuiz() allows a new alert).
function raiseAlert(student, req) {
  const page = String(req.page || req.level || "");
  const already = rows("alerts").some(function (a) {
    return String(a.username).toLowerCase() === student.username && String(a.page) === page;
  });
  if (already) return;
  const a = { date: new Date(), username: student.username, full_name: student.full_name, level: req.level,
              page: page, score_pct: req.pct,
              email: student.email || "", facebook: student.facebook || "", phone: student.phone || "" };
  addRow("alerts", a);
  if (!ALERT_EMAIL) return;
  MailApp.sendEmail(ALERT_EMAIL,
    "[Kobo course] " + student.full_name + " needs help (" + (req.page_name || page) + ", " + req.pct + " %)",
    "A student is below " + Math.round(PASS * 100) + " % on a session after " + MAX_ATTEMPTS +
    " attempts: the next session stays locked.\n\n" +
    "Name:      " + student.full_name + "\n" +
    "Username:  " + student.username + "\n" +
    "Level:     " + req.level + "\n" +
    "Session:   " + (req.page_name || page) + " (" + page + ")\n" +
    "Score:     " + req.pct + " %\n" +
    "E-mail:    " + (student.email || "-") + "\n" +
    "Facebook:  " + (student.facebook || "-") + "\n" +
    "Phone:     " + (student.phone || "-") + "\n\n" +
    "To unblock after talking with the student, either:\n" +
    " - run resetQuiz() to give 2 new attempts on the quiz of this session, or\n" +
    " - write the id of the NEXT session (e.g. 06-statistics) in the open_pages column of this student.\n\n" +
    "Their answers are in the 'scores' tab of the course Google Sheet.");
}

// ---- Teacher tools (run by hand from the editor) ---------------------------------

// Rebuilds the "dashboard" tab: one row per student, their level score and status
function refreshDashboard() {
  const idx = quizIndex();
  const sc = rows("scores"), prog = rows("progress");
  const sh = sheet("dashboard");
  sh.clear();
  const head = ["username", "full_name", "access_level", "last_update", "last_page"];
  LEVELS.forEach(function (l) { head.push(l + "_%", l + "_quizzes", l + "_status"); });
  head.push("needs_help_on", "email", "facebook", "phone");
  const al = rows("alerts");
  const data = [head];
  rows("students").forEach(function (s) {
    const u = String(s.username).trim().toLowerCase();
    if (!u) return;
    const p = prog.find(function (x) { return String(x.username).toLowerCase() === u; }) || {};
    const r = [u, s.full_name, s.level || "beginner", p.updated || "", p.last_page || ""];
    LEVELS.forEach(function (l) {
      if (!idx) { r.push("", "", "set SITE_URL"); return; }
      const res = levelResult(u, l, idx, sc, String(s.open_pages || "").split(/[,;\s]+/)
                    .map(function (x) { return x.trim().replace(/\.html$/, ""); }).filter(String));
      r.push(Math.round(100 * res.pct), res.done + "/" + res.n,
             res.n === 0 ? "" : res.passed ? "passed" : res.stuck ? "NEEDS HELP" : res.done ? "in progress" : "");
    });
    const open = String(s.open_pages || "");
    r.push(al.filter(function (a) { return String(a.username).toLowerCase() === u; })
             .map(function (a) { return a.page; }).join(", ") + (open ? " (opened: " + open + ")" : ""),
           s.email || "", s.facebook || "", s.phone || "");
    data.push(r);
  });
  sh.getRange(1, 1, data.length, head.length).setValues(data);
  sh.getRange(1, 1, 1, head.length).setFontWeight("bold");
  sh.setFrozenRows(1);
  sh.getRange(1, head.length + 2).setValue("Updated: " + new Date());
}

// Copies the whole spreadsheet into the Drive folder BACKUP_FOLDER (keeps the last 12)
function weeklyBackup() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const it = DriveApp.getFoldersByName(BACKUP_FOLDER);
  const folder = it.hasNext() ? it.next() : DriveApp.createFolder(BACKUP_FOLDER);
  const name = ss.getName() + " — backup " + Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd");
  DriveApp.getFileById(ss.getId()).makeCopy(name, folder);
  const files = [];
  const f = folder.getFiles();
  while (f.hasNext()) files.push(f.next());
  files.sort(function (a, b) { return b.getDateCreated() - a.getDateCreated(); });
  files.slice(12).forEach(function (x) { x.setTrashed(true); });
}

// Give one student new attempts on one quiz.
// 1. Edit the two values.  2. Select "resetQuiz" in the menu.  3. Run.
function resetQuiz() {
  const USER = "hrakoto";   // <- username
  const QUIZ = "s04";       // <- quiz id (s00…s10, p1…p6, i00…i13, ip1…ip6)

  const pr = rows("progress").find(function (x) { return String(x.username).toLowerCase() === USER; });
  if (pr) {
    const state = JSON.parse(pr.state_json || "{}");
    if (state.quizzes) delete state.quizzes[QUIZ];
    if (state.alerts) state.alerts = {};
    setCell("progress", pr._row, "state_json", JSON.stringify(state));
  }
  const sh = sheet("scores");
  rows("scores").reverse().forEach(function (r) {
    if (String(r.username).toLowerCase() === USER && String(r.quiz) === QUIZ) sh.deleteRow(r._row);
  });
  // forget the alert of that session, so that a new one can be sent if needed
  const idx = quizIndex(), page = idx && idx[QUIZ] ? idx[QUIZ].page : null;
  const al = sheet("alerts");
  rows("alerts").reverse().forEach(function (r) {
    if (String(r.username).toLowerCase() === USER && (!page || String(r.page) === page)) al.deleteRow(r._row);
  });
  Logger.log("Quiz " + QUIZ + " reset for " + USER + ". The student must log out and in again.");
}

// Test from the editor that the quiz list can be read from your site
function testQuizIndex() {
  CacheService.getScriptCache().remove("quiz_index");
  const idx = quizIndex();
  Logger.log(idx ? Object.keys(idx).length + " quizzes found." : "Quiz list NOT found: check SITE_URL.");
}
