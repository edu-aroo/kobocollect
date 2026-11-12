/* ============================================================================
   course.js  —  all the interactive behaviour of the course
   ----------------------------------------------------------------------------
   Loaded in the <head> of every page (see assets/header.html).
   Main parts (search for "PART" to jump):
     PART 1  Storage & communication with the Google Sheet (or demo mode)
     PART 2  Levels: which pages belong to which level, scores, unlocking
     PART 3  Login screen
     PART 4  Language switch (EN / FR)
     PART 5  Watermark, footer and navbar extras
     PART 6  Sidebar table of contents + "mark as done" + resume position
     PART 7  Quizzes (2 attempts, best attempt counts)
     PART 8  Help message, locked pages, hints, solutions, copy buttons
     PART 9  Home-page dashboard and certificates
     PART 10 Start-up
   JavaScript vocabulary for R users:
     const x = 5;      ~  x <- 5 (cannot be re-assigned)
     let x = 5;        ~  x <- 5 (can be re-assigned)
     function f(a){}   ~  f <- function(a){}
     obj.name          ~  obj$name
     array.map(f)      ~  lapply(vector, f)
     array.filter(f)   ~  x[sapply(x, f)]
     document.querySelectorAll(".quiz")  ~ "find every HTML element of class quiz"
   ============================================================================ */

(function () {               // everything inside this wrapper stays private
  "use strict";

  const CFG = window.COURSE_CONFIG;            // defined in config.js
  const QIDX = window.QUIZ_INDEX || {};        // defined in quiz_index.js (made by R/build_site.R)
  const DEMO = !CFG.scriptUrl;                 // no URL -> demo mode
  const AUTH_KEY = "kobo_auth";                  // sessionStorage key (current tab)
  const MAX_ATTEMPTS = CFG.maxAttempts || 2;
  const PASS = CFG.passThreshold || 0.75;      // share of the points needed (session and level)
  const COURSE_VERSION = 3;                    // version of the saved-progress format

  // The page id is the file name without ".html" ("index" for the home page)
  const PAGE_ID = (location.pathname.split("/").pop() || "index.html")
                    .replace(".html", "") || "index";

  let AUTH = null;     // {user, pass, name, level, role} once logged in
  let STATE = null;    // the student's progress object (saved in the sheet)
  let dirty = false;   // true when STATE changed but is not saved yet

  // t("English", "Français") -> bilingual snippet for HTML built in JS
  function t(en, fr) { return `<span class="en">${en}</span><span class="fr">${fr}</span>`; }

  // A new student starts with this empty state
  function emptyState() {
    const l = document.documentElement.classList.contains("lang-en") ? "en" : "fr";
    return { version: COURSE_VERSION, lang: l, lastPage: null, lastSection: null,
             pages: {}, quizzes: {}, certificates: {}, alerts: {} };
  }

  /* --------------------------------------------------------------------------
     PART 1 — Storage & communication
     api("login" | "save" | "score" | "unlock" | "stuck", data) -> Promise
     -------------------------------------------------------------------------- */
  async function api(action, data) {
    if (DEMO) return demoApi(action, data);
    // "text/plain" avoids a CORS "preflight" request that Apps Script refuses
    const res = await fetch(CFG.scriptUrl, {
      method: "POST",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify(Object.assign({ action: action }, data))
    });
    return res.json();
  }

  // Demo mode: same answers as the Google Sheet, but saved in the browser
  function demoApi(action, data) {
    const u = CFG.demoUsers.find(d => d.user === data.user && d.pass === data.pass);
    if (!u) return Promise.resolve({ ok: false, error: "bad_login" });
    const key = "kobo_state_" + u.user;
    if (action === "login") {
      let st = null;
      try { st = JSON.parse(localStorage.getItem(key)); } catch (e) {}
      return Promise.resolve({ ok: true, name: u.name, level: u.level, role: u.role, state: st,
                               levels: String(u.level).split(/[,;\s]+/).filter(x => x) });
    }
    if (action === "unlock") {
      const code = "DEMO-" + data.passed.slice(0, 3).toUpperCase() + "-" + Date.now().toString(36).toUpperCase();
      return Promise.resolve({ ok: true, level: data.level,
        certificate: { code: code, date: new Date().toISOString().slice(0, 10), pct: data.pct } });
    }
    if (action === "save") { try { localStorage.setItem(key, JSON.stringify(data.state)); } catch (e) {} }
    return Promise.resolve({ ok: true });
  }

  function cacheState() {   // copy of the state for the next page opened in this tab
    if (STATE) try { sessionStorage.setItem("kobo_state_cache", JSON.stringify(STATE)); } catch (e) {}
  }
  window.addEventListener("pagehide", cacheState);

  let saveTimer = null;     // save at most once every 2 seconds ("debounce")
  function saveSoon() {
    dirty = true; cacheState();
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveNow, 2000);
  }
  function saveNow() {
    if (!AUTH || !dirty) return;
    dirty = false; cacheState();
    setSaveStatus("saving");
    api("save", { user: AUTH.user, pass: AUTH.pass, state: STATE })
      .then(r => setSaveStatus(r.ok ? "saved" : "error"))
      .catch(() => { dirty = true; setSaveStatus("error"); });
  }
  // When the tab closes: send the last changes with sendBeacon (works while closing)
  window.addEventListener("pagehide", function () {
    if (!AUTH || !dirty) return;
    if (DEMO) { saveNow(); return; }
    const body = JSON.stringify({ action: "save", user: AUTH.user, pass: AUTH.pass, state: STATE });
    navigator.sendBeacon(CFG.scriptUrl, new Blob([body], { type: "text/plain" }));
  });

  // Progress saved by an older version of the course is upgraded here.
  // Version 3 keeps all beginner page and quiz ids, so nothing is renamed:
  // we only add the new fields. (Version 1 -> 2 renamed pages: see README.)
  function migrateState(st) {
    st = st || {};
    const v = st.version || 1;
    if (v < 2) {
      const keep = { s01: "s01", s03: "s03", s05: "s06", s06: "s07", s09: "s10" };
      const q = {}, legacy = st.legacy || {};
      Object.keys(st.quizzes || {}).forEach(id => {
        if (keep[id]) q[keep[id]] = st.quizzes[id]; else legacy["v1_" + id] = st.quizzes[id];
      });
      st.quizzes = q; st.legacy = legacy;
      const pageMap = { "04-cleaning": "05-cleaning", "05-statistics": "06-statistics",
                        "06-graphics": "07-graphics", "08-tidyverse": "08-packages-tidyverse",
                        "09-final-project": "10-final-project", "07-functions": null };
      const pages = {};
      Object.keys(st.pages || {}).forEach(id => {
        const nid = (id in pageMap) ? pageMap[id] : id;
        if (nid) pages[nid] = st.pages[id];
      });
      st.pages = pages;
      if (st.lastPage in pageMap) { st.lastPage = pageMap[st.lastPage]; st.lastSection = null; }
    }
    st.certificates = st.certificates || {};
    st.alerts = st.alerts || {};
    // A quiz that changed size keeps the student's percentage: 9/12 -> 7.5/10.
    Object.keys(st.quizzes || {}).forEach(id => {
      const q = st.quizzes[id], m = QIDX[id] && QIDX[id].max;
      if (!q || !m || !q.max || q.max === m) return;
      const r = v => Math.round(10 * (v || 0) * m / q.max) / 10;
      q.best = r(q.best); q.score = r(q.score); q.max = m;
    });
    // never send a student to a page that does not exist
    if (st.lastPage && allPageIds().indexOf(st.lastPage) === -1) { st.lastPage = null; st.lastSection = null; }
    st.version = COURSE_VERSION;
    return st;
  }

  /* --------------------------------------------------------------------------
     PART 2 — Levels
     -------------------------------------------------------------------------- */
  const LEVEL_IDS = CFG.levels.map(l => l.id);                 // ["beginner", "intermediate", "advanced"]
  function allPageIds() {
    return CFG.levels.flatMap(l => l.pages.map(p => p.id)).concat(CFG.extraPages);
  }
  function levelOfPage(pageId) {
    const l = CFG.levels.find(l => l.pages.some(p => p.id === pageId));
    return l ? l.id : null;                                    // null = page outside levels
  }
  function levelName(id) { const l = CFG.levels.find(x => x.id === id); return l ? t(l.en, l.fr) : id; }
  function isTeacher() { return AUTH && AUTH.role === "teacher"; }

  // Score of a level, from the quiz index (all quizzes of the level, even unopened)
  //   earned   = sum of the best attempt of each quiz
  //   total    = sum of the number of questions of all quizzes of the level
  //   possible = best score still reachable (full marks where attempts remain)
  //   Quizzes of SKIPPED sessions are left out (see isSkipped below).
  function levelStats(levelId) {
    const ids = Object.keys(QIDX).filter(id => QIDX[id].level === levelId && !isSkipped(QIDX[id].page));
    let earned = 0, total = 0, possible = 0, done = 0;
    ids.forEach(id => {
      const max = QIDX[id].max, q = STATE.quizzes[id];
      total += max;
      if (q) { done++; earned += q.best; }
      possible += (q && q.attempts >= MAX_ATTEMPTS) ? q.best : max;
    });
    const n = ids.length;
    return { n: n, done: done, earned: earned, total: total,
             pct: total ? earned / total : 0,
             complete: n > 0 && done === n,
             passed: n > 0 && done === n && earned >= PASS * total - 1e-9 };
  }

  // ---- Sessions (pages) inside a level ---------------------------------------
  // Each session must be finished with PASS (75 %) of its points before the next
  // one opens. A practice page with several quizzes counts as ONE session: 75 % of
  // the total points of its quizzes.
  function pageQuizIds(p) { return p.quizzes || (p.quiz ? [p.quiz] : []); }
  function findPage(pageId) {                          // -> {level, i, page} or null
    for (const l of CFG.levels) {
      const i = l.pages.findIndex(p => p.id === pageId);
      if (i !== -1) return { level: l, i: i, page: l.pages[i] };
    }
    return null;
  }
  function pageName(pageId, lang) {
    const f = findPage(pageId); return f ? f.page[lang] : pageId;
  }
  function pageStats(pageId) {
    const f = findPage(pageId);
    const ids = f ? pageQuizIds(f.page) : [];
    let earned = 0, total = 0, possible = 0, done = 0;
    ids.forEach(id => {
      const q = STATE.quizzes[id];
      const max = (QIDX[id] && QIDX[id].max) || (q && q.max) || 0;
      total += max;
      if (q) { done++; earned += q.best; }
      possible += (q && q.attempts >= MAX_ATTEMPTS) ? q.best : max;
    });
    const n = ids.length;
    return { n: n, done: done, earned: earned, total: total,
             pct: total ? earned / total : 0,
             complete: n > 0 && done === n,
             passed: n === 0 || (done === n && earned >= PASS * total - 1e-9),
             stuck: n > 0 && possible < PASS * total - 1e-9 };
  }
  // A session is SKIPPED when the teacher let the student jump over it: it comes
  // BEFORE a session listed in "open_pages" (same level) and the student has not
  // started its quiz. Skipped sessions do not count in the level's 75 %.
  // (Sessions done anyway, even after skipping, count normally.)
  function isSkipped(pageId) {
    if (!AUTH || isTeacher()) return false;
    const f = findPage(pageId);
    if (!f) return false;
    if (pageQuizIds(f.page).some(id => STATE.quizzes[id])) return false;
    return (AUTH.openPages || []).some(op => {
      const g = findPage(op);
      return g && g.level.id === f.level.id && g.i > f.i;
    });
  }

  // Pages the teacher opened by hand (column "open_pages" of the Google Sheet)
  function manuallyOpened(pageId) {
    return (AUTH.openPages || []).indexOf(pageId) !== -1;
  }
  // A session is open if: teacher; its level is open AND (it is the first session of
  // the level, or the previous session is passed, or the teacher opened it, or the
  // student already started its quiz, or the student was given a higher level).
  function isPageOpen(pageId) {
    if (isTeacher()) return true;
    const f = findPage(pageId);
    if (!f) return true;                                 // home page, help, cheatsheets…
    if (!isUnlocked(f.level.id)) return false;
    if (f.i === 0 || manuallyOpened(pageId) || isSkipped(pageId)) return true;   // skipped = open for revision
    if (pageQuizIds(f.page).some(id => STATE.quizzes[id])) return true;   // work already started is never hidden
    return pageStats(f.level.pages[f.i - 1].id).passed;
  }
  function levelHasStuckPage(levelId) {
    const l = CFG.levels.find(x => x.id === levelId);
    return !!l && l.pages.some(p => isPageOpen(p.id) && pageStats(p.id).stuck && !manuallyOpenedNext(p.id));
  }
  // the teacher already opened the session after a stuck one: no more "needs help"
  function manuallyOpenedNext(pageId) {
    const f = findPage(pageId);
    const nxt = f && f.level.pages[f.i + 1];
    return !!nxt && manuallyOpened(nxt.id);
  }

  // Levels the student registered for = column "level" of the Google Sheet,
  // e.g. "beginner", "intermediate, advanced", "beginner, intermediate, advanced".
  function grantedLevels() {
    const g = (AUTH && AUTH.levels && AUTH.levels.length) ? AUTH.levels : [(AUTH && AUTH.level) || "beginner"];
    return LEVEL_IDS.filter(id => g.indexOf(id) !== -1);          // in course order
  }
  // A level is open if: teacher; or it is in the student's list AND it is the first
  // level of the list, or the previous level of the list is passed.
  function isUnlocked(levelId) {
    if (isTeacher()) return true;
    const g = grantedLevels(), k = g.indexOf(levelId);
    if (k === -1) return false;                       // not in the registration
    if (k === 0) return true;                         // starting level
    return isUnlocked(g[k - 1]) && levelStats(g[k - 1]).passed;
  }

  // Called after each quiz of the page:
  //  1. session stuck (75 % out of reach after the attempts) -> alert the teacher once
  //     and send the student to the help page;
  //  2. session newly passed -> say that the next session is open;
  //  3. level passed -> unlock the next level (server records it, e-mails the teacher
  //     and issues a certificate).
  function checkProgress(pageId, wasPassed) {
    if (isTeacher()) return;
    const f = findPage(pageId);
    if (!f) return;
    const ps = pageStats(pageId), levelId = f.level.id;
    const optional = false;
    if (ps.stuck && !optional && !manuallyOpenedNext(pageId)) {
      if (!STATE.alerts[pageId]) {
        STATE.alerts[pageId] = new Date().toISOString();
        saveSoon();
        api("stuck", { user: AUTH.user, pass: AUTH.pass, level: levelId, page: pageId,
                       page_name: pageName(pageId, "en"), pct: Math.round(100 * ps.pct) }).catch(() => {});
      }
      goToHelp(pageId);
      return;
    }
    const st = levelStats(levelId);
    const next = LEVEL_IDS[LEVEL_IDS.indexOf(levelId) + 1];
    const nextGranted = !!next && grantedLevels().indexOf(next) !== -1;
    const inProgress = !!f.level.inProgress;          // level still being written: no certificate yet
    if (st.passed && !inProgress && !STATE.certificates[levelId]) {
      api("unlock", { user: AUTH.user, pass: AUTH.pass, passed: levelId, level: next,
                      pct: Math.round(100 * st.pct) })
        .then(r => {
          if (!r.ok) return;
          if (r.certificate) STATE.certificates[levelId] = r.certificate;
          saveSoon();
          showModal(`<h2>${t("Congratulations!", "Félicitations !")} 🎉</h2>
            <p>${t(`You passed the <b>${levelLabel(levelId, "en")}</b> level with <b>${Math.round(100 * st.pct)} %</b>.`,
                   `Vous avez validé le niveau <b>${levelLabel(levelId, "fr")}</b> avec <b>${Math.round(100 * st.pct)} %</b>.`)}</p>
           ${next ? (nextGranted
              ? `<p>${t(`The <b>${levelLabel(next, "en")}</b> level is now open.`,
                        `Le niveau <b>${levelLabel(next, "fr")}</b> est maintenant ouvert.`)}</p>`
              : `<p>${t(`To continue with the <b>${levelLabel(next, "en")}</b> level, <a href="help.html">contact me</a>.`,
                        `Pour continuer avec le niveau <b>${levelLabel(next, "fr")}</b>, <a href="help.html">contactez-moi</a>.`)}</p>`) : ""}
            <p><a class="rc-continue" href="certificate.html?level=${levelId}">${t("See my certificate", "Voir mon certificat")}</a></p>`);
        }).catch(() => {});
    } else if (ps.passed && !wasPassed) {
      const nxt = f.level.pages[f.i + 1];
      if (nxt) showModal(`<h2>${t("Session passed!", "Séance validée !")} ✓</h2>
        <p>${t(`You got <b>${Math.round(100 * ps.pct)} %</b> on this session.`, `Vous avez obtenu <b>${Math.round(100 * ps.pct)} %</b> à cette séance.`)}</p>
        <p>${t(`The next session is open: <b>${nxt.en}</b>.`, `La séance suivante est ouverte : <b>${nxt.fr}</b>.`)}</p>
        <p><a class="rc-continue" href="${nxt.id}.html">${t("Go to the next session", "Aller à la séance suivante")} →</a></p>`);
    }
  }
  // Stuck: short message, then the help page (the student can stay to read the solution)
  function goToHelp(pageId) {
    const url = "help.html?page=" + encodeURIComponent(pageId);
    const m = showModal(`<h2>${t(`Below ${Math.round(PASS * 100)} % after ${MAX_ATTEMPTS} attempts`,
                                 `Moins de ${Math.round(PASS * 100)} % après ${MAX_ATTEMPTS} tentatives`)}</h2>
      <p>${t("You will now be taken to the help page, with my contacts.",
             "Vous allez être redirigé vers la page d'aide, avec mes contacts.")}</p>
      <p><a class="rc-continue" href="${url}">${t("Go to the help page", "Aller à la page d'aide")} →</a></p>
      <p><small>${t("Or close this window within 10 seconds to read the solution first.",
                    "Ou fermez cette fenêtre dans les 10 secondes pour lire d'abord la solution.")}</small></p>`);
    const timer = setTimeout(() => { saveNow(); location.href = url; }, 10000);
    m.querySelector(".rc-modal-close").addEventListener("click", () => clearTimeout(timer));
  }
  function levelLabel(id, lang) { const l = CFG.levels.find(x => x.id === id); return l ? l[lang] : id; }

  /* --------------------------------------------------------------------------
     PART 3 — Login screen
     -------------------------------------------------------------------------- */
  function showLogin() {
    const box = document.createElement("div");
    box.id = "rc-login";
    box.style.backgroundImage = `url("${CFG.loginBackground}")`;
    box.innerHTML = `
      <div class="rc-login-card">
        <div class="rc-login-wave" aria-hidden="true"></div>
         <img class="rc-login-logo" src="assets/img/logo.png" alt="Logo">
        <h1>${t(CFG.title.en, CFG.title.fr)}</h1>
        <p class="rc-login-sub">${t(CFG.subtitle.en, CFG.subtitle.fr)}</p>
        <form>
          <label>${t("Username", "Identifiant")}
            <input name="user" autocomplete="username" required></label>
          <label>${t("Password", "Mot de passe")}
            <input name="pass" type="password" autocomplete="current-password" required></label>
          <button type="submit">${t("Enter the course", "Entrer dans le cours")}</button>
          <p class="rc-login-msg" role="alert"></p>
        </form>
        ${DEMO ? '<p class="rc-demo">Demo mode — <b>demo</b> / <b>demo</b> · teacher: <b>teacher</b> / <b>teacher</b></p>' : ""}
        <p class="rc-login-lang">
          <button type="button" data-lang="fr">Français</button> ·
          <button type="button" data-lang="en">English</button>
        </p>
        <p class="rc-login-by">by ${CFG.author}</p>
        <p class="rc-privacy">${t(
          "Privacy: your name, progress and quiz answers are stored in the teacher's Google Sheet, only to follow your learning and issue certificates. Ask the teacher to see or delete them.",
          "Confidentialité : votre nom, votre progression et vos réponses aux quiz sont enregistrés dans le Google Sheet de l'enseignante, uniquement pour suivre votre apprentissage et délivrer les certificats. Demandez-lui pour les consulter ou les supprimer.")}</p>
      </div>`;
    document.body.appendChild(box);
    box.querySelectorAll("[data-lang]").forEach(b =>
      b.addEventListener("click", () => applyLang(b.dataset.lang)));

    const form = box.querySelector("form");
    form.addEventListener("submit", async function (ev) {
      ev.preventDefault();                       // stop the browser reloading the page
      const user = form.user.value.trim().toLowerCase();
      const pass = form.pass.value;
      const msg = box.querySelector(".rc-login-msg");
      msg.innerHTML = t("Checking…", "Vérification…");
      try {
        const r = await api("login", { user: user, pass: pass });
        if (!r.ok) { msg.innerHTML = t("Wrong username or password.", "Identifiant ou mot de passe incorrect."); return; }
        AUTH = { user: user, pass: pass, name: r.name || user,
                 level: r.level || "beginner", levels: r.levels || null, role: r.role || "student",
                 openPages: r.openPages || [] };
        sessionStorage.setItem(AUTH_KEY, JSON.stringify(AUTH));
        STATE = r.state ? Object.assign(emptyState(), migrateState(r.state)) : emptyState();
        cacheState();
        // Resume: jump to the page and section where the student stopped
        if (STATE.lastPage && STATE.lastPage !== PAGE_ID) {
          location.href = STATE.lastPage + ".html" + (STATE.lastSection ? "#" + STATE.lastSection : "");
          return;
        }
        box.remove();
        start(true);
      } catch (e) {
        msg.innerHTML = t("Cannot reach the server. Check your internet connection.",
                          "Serveur injoignable. Vérifiez votre connexion internet.");
      }
    });
  }

  function logout() {
    saveNow();
    sessionStorage.removeItem(AUTH_KEY);
    sessionStorage.removeItem("kobo_state_cache");
    setTimeout(() => location.href = "index.html", 400);
  }

  /* --------------------------------------------------------------------------
     PART 4 — Language switch
     CSS rule (course.css): html.lang-fr .en {display:none} and vice versa.
     -------------------------------------------------------------------------- */
  function currentLang() { return document.documentElement.classList.contains("lang-en") ? "en" : "fr"; }
  function applyLang(lang) {
    const h = document.documentElement;
    h.classList.remove("lang-en", "lang-fr");
    h.classList.add("lang-" + lang);
    h.setAttribute("lang", lang);
    try { localStorage.setItem("kobo_lang", lang); } catch (e) {}
    if (STATE && STATE.lang !== lang) { STATE.lang = lang; saveSoon(); }
  }

  /* --------------------------------------------------------------------------
     PART 5 — Watermark, footer, navbar extras
     -------------------------------------------------------------------------- */
  function addWatermark() {
    // An SVG tile with the author name, repeated diagonally in the background
    const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='360' height='220'>
      <text x='20' y='140' transform='rotate(-24 180 110)' font-family='Georgia,serif'
      font-size='20' fill='#0b3d5c' fill-opacity='0.055'>by ${CFG.author}</text></svg>`;
    const wm = document.createElement("div");
    wm.className = "rc-watermark";
    wm.style.backgroundImage = 'url("data:image/svg+xml;utf8,' + encodeURIComponent(svg) + '")';
    document.body.appendChild(wm);

    const foot = document.createElement("footer");
    foot.className = "rc-footer";
    foot.innerHTML = `<span class="rc-sign">by ${CFG.author}</span>
      <span>© ${new Date().getFullYear()} · ${t("Course material — please do not redistribute without permission",
                                                  "Support de cours — merci de ne pas diffuser sans autorisation")}
      · <a href="whats-new.html">v${CFG.version} (${CFG.versionDate})</a></span>`;
    (document.querySelector(".main-container") || document.body).appendChild(foot);
  }

  function addNavbarExtras() {
    const nav = document.querySelector(".navbar .navbar-collapse") || document.querySelector(".navbar");
    if (!nav) return;
    const ul = document.createElement("ul");
    ul.className = "nav navbar-nav navbar-right rc-nav-extra";
    ul.innerHTML = `
      <li><a href="#" class="rc-lang-btn" title="Language / Langue">${t("FR", "EN")}</a></li>
      <li><span class="rc-user">${AUTH.name}${isTeacher() ? ' <span class="rc-badge">teacher</span>' : ""}</span>
          <span class="rc-save" data-s=""></span></li>
      <li><a href="#" class="rc-logout">${t("Log out", "Déconnexion")}</a></li>`;
    nav.appendChild(ul);
    ul.querySelector(".rc-lang-btn").addEventListener("click", e => {
      e.preventDefault(); applyLang(currentLang() === "en" ? "fr" : "en");
    });
    ul.querySelector(".rc-logout").addEventListener("click", e => { e.preventDefault(); logout(); });
    // padlocks on the links of locked levels in the navbar menus
    document.querySelectorAll(".navbar a[href$='.html']").forEach(a => {
      if (!isPageOpen(a.getAttribute("href").replace(".html", ""))) a.classList.add("rc-locked-link");
    });
  }
  function setSaveStatus(s) {
    const el = document.querySelector(".rc-save");
    if (!el) return;
    el.dataset.s = s;
    el.innerHTML = s === "saving" ? t("saving…", "enregistrement…")
                 : s === "saved"  ? t("saved", "enregistré")
                 : t("not saved — check connection", "non enregistré — vérifiez la connexion");
  }

  /* --------------------------------------------------------------------------
     PART 6 — Sidebar table of contents, "mark as done", resume position
     Each "## Title" in the .Rmd becomes <div class="section level2" id="...">.
     -------------------------------------------------------------------------- */
  function pageState() {
    STATE.pages[PAGE_ID] = STATE.pages[PAGE_ID] || { done: [], total: 0 };
    return STATE.pages[PAGE_ID];
  }

  function buildSections() {
    const main = document.querySelector(".main-container");
    const secs = Array.from(main.querySelectorAll("div.section.level2"))
                      .filter(s => !s.classList.contains("no-track"));
    if (!secs.length || PAGE_ID === "index") return;
    const ps = pageState();
    ps.total = secs.length;
    const ids = secs.map(x => x.id);
    ps.done = ps.done.filter(id => ids.indexOf(id) !== -1);   // ignore sections that no longer exist

    const side = document.createElement("nav");
    side.className = "rc-side";
    side.innerHTML = `<div class="rc-side-title">${t("In this session", "Dans cette séance")}</div>
      <div class="rc-progress"><div class="rc-progress-bar"></div></div>
      <div class="rc-progress-label"></div><ol></ol>`;
    const ol = side.querySelector("ol");
    secs.forEach(sec => {
      const h = sec.querySelector("h2");
      const li = document.createElement("li");
      li.dataset.id = sec.id;
      li.innerHTML = `<a href="#${sec.id}">${h.innerHTML}</a>`;   // innerHTML keeps EN/FR spans
      ol.appendChild(li);
      const btn = document.createElement("button");               // "mark as done" button
      btn.className = "rc-done-btn";
      btn.addEventListener("click", () => {
        const i = ps.done.indexOf(sec.id);
        if (i === -1) ps.done.push(sec.id); else ps.done.splice(i, 1);
        refresh(); saveSoon();
      });
      sec.appendChild(btn);
      sec._btn = btn;
    });
    document.body.appendChild(side);

    function refresh() {
      secs.forEach(sec => {
        const done = ps.done.indexOf(sec.id) !== -1;
        sec.classList.toggle("rc-is-done", done);
        sec._btn.innerHTML = done ? t("✓ Section done (click to undo)", "✓ Section terminée (cliquer pour annuler)")
                                  : t("Mark this section as done", "Marquer cette section comme terminée");
        side.querySelector(`li[data-id="${sec.id}"]`).classList.toggle("done", done);
      });
      const pct = Math.round(100 * ps.done.length / ps.total);
      side.querySelector(".rc-progress-bar").style.width = pct + "%";
      side.querySelector(".rc-progress-label").innerHTML = pct + " % " + t("completed", "terminé");
    }
    refresh();

    // remember the section currently on screen (to resume later)
    const obs = new IntersectionObserver(entries => {
      entries.forEach(en => {
        if (en.isIntersecting) {
          const id = en.target.parentElement.id;
          side.querySelectorAll("li").forEach(li => li.classList.toggle("current", li.dataset.id === id));
          if (STATE.lastSection !== id) { STATE.lastSection = id; saveSoon(); }
        }
      });
    }, { rootMargin: "0px 0px -70% 0px" });
    secs.forEach(sec => obs.observe(sec.querySelector("h2")));
  }

  /* --------------------------------------------------------------------------
     PART 7 — Quizzes. The R helper quiz() writes <div class="quiz" data-q="BASE64(JSON)">.
     Rules: MAX_ATTEMPTS attempts; the BEST attempt counts; after an attempt the
     wrong questions are shown in red (not the right value); the solution opens
     when no attempt is left or the score is perfect.
     -------------------------------------------------------------------------- */
  function decode(b64) {
    const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));   // atob() decodes base64
    return JSON.parse(new TextDecoder().decode(bytes));               // TextDecoder keeps accents
  }
  function norm(s) { return String(s).trim().toLowerCase().replace(/\s+/g, " "); }
  function toNumber(s) { return parseFloat(String(s).replace(",", ".").replace(/[^0-9.\-eE]/g, "")); }
  function quizFinished(q, max) { return q && (q.attempts >= MAX_ATTEMPTS || q.best === max); }

  function skippedNote() {
    if (!isSkipped(PAGE_ID)) return;
    document.querySelectorAll(".quiz").forEach(el => {
      const n = document.createElement("p");
      n.className = "rc-quiz-rule rc-skip-note";
      n.innerHTML = t("<b>You are exempted from this session.</b> Its quiz is optional and does not count in your level score — unless you take it: then it counts like any other quiz.",
                      "<b>Vous êtes dispensé de cette séance.</b> Son quiz est facultatif et ne compte pas dans votre score du niveau — sauf si vous le faites : il compte alors comme les autres quiz.");
      el.prepend(n);
    });
  }
  function buildQuizzes() {
    document.querySelectorAll(".quiz").forEach(el => {
      const id = el.dataset.quizId;
      const qs = decode(el.dataset.q);
      const title = el.dataset.titleEn
        ? t(el.dataset.titleEn, el.dataset.titleFr)
        : t("Quiz — enter the results of your application work",
            "Quiz — saisissez les résultats de votre travail d'application");
      let html = `<h3 class="rc-quiz-title">${title}</h3>
        <p class="rc-quiz-rule">${isTeacher()
          ? t("<b>Teacher mode:</b> your answers are checked but never recorded.",
              "<b>Mode enseignant :</b> vos réponses sont vérifiées mais jamais enregistrées.")
          : t(`<b>${MAX_ATTEMPTS} attempts.</b> Your best attempt counts. Check your answers in your script before submitting.`,
              `<b>${MAX_ATTEMPTS} tentatives.</b> Votre meilleure tentative compte. Vérifiez vos réponses dans votre script avant de valider.`)}</p>
        <ol class="rc-q-list">`;
      qs.forEach((q, i) => {
        html += `<li class="rc-q" data-i="${i}"><div class="rc-q-text">${t(q.en, q.fr)}</div>`;
        if (q.type === "mcq") {
          q.options_en.forEach((o, j) => {
            html += `<label class="rc-opt"><input type="radio" name="${id}-${i}" value="${j}">
                     ${t(o, q.options_fr[j])}</label>`;
          });
        } else {
          html += `<input class="rc-input" type="text" inputmode="${q.type === "num" ? "decimal" : "text"}"
                   placeholder="${q.type === "num" ? "e.g. 12.5" : "…"}">`;
          if (q.hint_en) html += `<div class="rc-hint">${t(q.hint_en, q.hint_fr)}</div>`;
        }
        html += `<div class="rc-feedback"></div></li>`;
      });
      html += `</ol><div class="rc-actions"><button class="rc-submit">${t("Submit my answers", "Valider mes réponses")}</button>
               <button class="rc-cancel" hidden>${t("Go back", "Revenir")}</button></div>
               <p class="rc-warn"></p><div class="rc-score"></div>`;
      el.innerHTML = html;

      const prev = STATE.quizzes[id];
      if (prev) {
        if (prev.answers) fill(el, qs, prev.answers);
        showFeedback(el, qs, prev.answers || []);
        showScore(el, prev);
        if (quizFinished(prev, qs.length)) lockQuiz(el);
      }

      // Two-step submit: 1st click asks for confirmation, 2nd click grades
      const btn = el.querySelector(".rc-submit"), cancel = el.querySelector(".rc-cancel");
      const warn = el.querySelector(".rc-warn");
      let armed = false;
      btn.addEventListener("click", () => {
        if (!armed && !isTeacher()) {
          const ans = readAnswers(el, qs);
          const empty = ans.filter(a => a === null || String(a).trim() === "").length;
          const used = (STATE.quizzes[id] || {}).attempts || 0;
          const left = MAX_ATTEMPTS - used - 1;
          warn.innerHTML = (empty ? t(`${empty} question(s) not answered. `, `${empty} question(s) sans réponse. `) : "")
            + (left > 0 ? t(`After this attempt you will have ${left} attempt(s) left. Submit?`,
                            `Après cette tentative, il vous restera ${left} tentative(s). Valider ?`)
                        : t("This is your LAST attempt. Submit?", "C'est votre DERNIÈRE tentative. Valider ?"));
          btn.innerHTML = t("Yes, submit", "Oui, valider");
          btn.classList.add("rc-armed"); cancel.hidden = false; armed = true;
          return;
        }
        armed = false; cancel.hidden = true; warn.innerHTML = "";
        btn.classList.remove("rc-armed");
        btn.innerHTML = t("Submit my answers", "Valider mes réponses");
        grade(el, id, qs);
      });
      cancel.addEventListener("click", () => {
        armed = false; cancel.hidden = true; warn.innerHTML = "";
        btn.classList.remove("rc-armed");
        btn.innerHTML = t("Submit my answers", "Valider mes réponses");
      });
    });
  }

  function lockQuiz(el) {
    el.classList.add("rc-locked");
    el.querySelectorAll("input").forEach(i => i.disabled = true);
    el.querySelector(".rc-actions").hidden = true;
  }
  function readAnswers(el, qs) {
    return qs.map((q, i) => {
      const li = el.querySelector(`.rc-q[data-i="${i}"]`);
      if (q.type === "mcq") { const r = li.querySelector("input:checked"); return r ? Number(r.value) : null; }
      return li.querySelector(".rc-input").value;
    });
  }
  function fill(el, qs, ans) {
    qs.forEach((q, i) => {
      const li = el.querySelector(`.rc-q[data-i="${i}"]`);
      if (ans[i] === null || ans[i] === undefined) return;
      if (q.type === "mcq") { const r = li.querySelector(`input[value="${ans[i]}"]`); if (r) r.checked = true; }
      else li.querySelector(".rc-input").value = ans[i];
    });
  }
  function isCorrect(q, a) {
    if (a === null || a === undefined || a === "") return false;
    if (q.type === "mcq") return a === q.answer;
    if (q.type === "num") { const x = toNumber(a); return !isNaN(x) && Math.abs(x - q.answer) <= q.tol + 1e-9; }
    return q.answer.map(norm).indexOf(norm(a)) !== -1;
  }
  function showFeedback(el, qs, ans) {
    let score = 0;
    qs.forEach((q, i) => {
      const ok = isCorrect(q, ans[i]);
      if (ok) score++;
      const li = el.querySelector(`.rc-q[data-i="${i}"]`);
      li.classList.remove("ok", "ko"); li.classList.add(ok ? "ok" : "ko");
      li.querySelector(".rc-feedback").innerHTML = ok ? t("Correct", "Correct")
        : t("Incorrect — check this step in your script.", "Incorrect — vérifiez cette étape dans votre script.");
    });
    return score;
  }

  function grade(el, id, qs) {
    const ans = readAnswers(el, qs);
    const score = showFeedback(el, qs, ans);
    if (isTeacher()) {                                  // teacher: check only, record nothing
      el.querySelector(".rc-score").innerHTML = `<div>${t("Score", "Score")}: <b>${score}/${qs.length}</b> (${t("not recorded", "non enregistré")})</div>`;
      return;
    }
    const wasPassed = findPage(PAGE_ID) ? pageStats(PAGE_ID).passed && pageStats(PAGE_ID).complete : false;
    const prev = STATE.quizzes[id] || { best: 0, attempts: 0 };
    const rec = { score: score, max: qs.length, best: Math.max(prev.best || 0, score),
                  attempts: (prev.attempts || 0) + 1, date: new Date().toISOString(), answers: ans };
    STATE.quizzes[id] = rec;
    showScore(el, rec);
    if (quizFinished(rec, qs.length)) lockQuiz(el);
    unlockSolutions();
    dirty = true; saveNow();
    if (!DEMO) api("score", { user: AUTH.user, pass: AUTH.pass, quiz: id, page: PAGE_ID,
                              score: score, max: qs.length, attempt: rec.attempts, answers: ans }).catch(() => {});
    checkProgress(PAGE_ID, wasPassed);
  }
  function showScore(el, rec) {
    const pct = Math.round(100 * rec.best / rec.max);
    const left = MAX_ATTEMPTS - rec.attempts;
    el.querySelector(".rc-score").innerHTML = `
      <div class="rc-score-ring" style="--p:${pct}"><span>${rec.best}/${rec.max}</span></div>
      <div>${t("Best score", "Meilleur score")}: <b>${rec.best}/${rec.max}</b> (${pct} %) ·
           ${t("Last attempt", "Dernière tentative")}: ${rec.score}/${rec.max} ·
           ${t("Attempts", "Tentatives")}: ${rec.attempts}/${MAX_ATTEMPTS}<br>
           <small>${quizFinished(rec, rec.max)
             ? t("Quiz finished. The solution below is now open: study it, especially the questions in red.",
                 "Quiz terminé. La solution ci-dessous est ouverte : étudiez-la, surtout les questions en rouge.")
             : t(`Correct the questions in red in your script, then use your ${left} remaining attempt(s).`,
                 `Corrigez les questions en rouge dans votre script, puis utilisez votre/vos ${left} tentative(s) restante(s).`)}</small></div>`;
  }

  /* --------------------------------------------------------------------------
     PART 8 — Help message, locked pages, hints, solutions, copy buttons
     -------------------------------------------------------------------------- */
  // The help message (text by Aroo Falinirina). pageId = the session where the student is stuck.
  function helpMessage(pageId) {
    const c = CFG.contact, p = Math.round(PASS * 100);
    const ps = findPage(pageId) ? pageStats(pageId) : null;
    return `<h2>${t(`Two attempts done, but still not the ${p} % needed to move on to the next session?`,
                    `Deux tentatives au compteur, mais toujours pas les ${p} % nécessaires pour passer à la séance suivante ?`)}</h2>
      <p>${t("Don't panic! Even R sometimes struggles to count from 1… and it's supposed to be good with numbers! 😄",
             "Pas de panique ! Même R a parfois du mal à compter à partir de 1… et pourtant, il est censé être doué avec les chiffres ! 😄")}</p>
      <p>${t("Maybe it's time for a little session together! We'll look at what's going wrong, track down the small errors and get your script back on track.",
             "C'est peut-être le moment de faire une petite séance ensemble ! On va examiner ce qui coince, débusquer les petites erreurs et remettre votre script sur la bonne voie.")}</p>
      <p>${t("Contact me", "Contactez-moi")} :<br>
         ✉ <a href="mailto:${c.email}">${c.email}</a><br>
         💬 Facebook : <b>${c.facebook}</b></p>
      ${ps ? `<p><small>${t(`Mention your username (<b>${AUTH.user}</b>) and the session (<b>${pageName(pageId, "en")}</b>, your score: ${Math.round(100 * ps.pct)} %).`,
                           `Indiquez votre identifiant (<b>${AUTH.user}</b>) et la séance (<b>${pageName(pageId, "fr")}</b>, votre score : ${Math.round(100 * ps.pct)} %).`)}</small></p>
             <p><a href="${pageId}.html#application">${t("Back to the session (quiz and solution)", "Retour à la séance (quiz et solution)")}</a></p>`
           : `<p><small>${t(`Mention your username (<b>${AUTH.user}</b>).`, `Indiquez votre identifiant (<b>${AUTH.user}</b>).`)}</small></p>`}`;
  }

  function showModal(html) {
    const m = document.createElement("div");
    m.className = "rc-modal";
    m.innerHTML = `<div class="rc-modal-card">${html}<button class="rc-modal-close">${t("Close", "Fermer")}</button></div>`;
    document.body.appendChild(m);
    m.querySelector(".rc-modal-close").addEventListener("click", () => m.remove());
    return m;
  }

  // A page of a locked level: hide the content, show what is needed
  function lockPageIfNeeded() {
    const lv = levelOfPage(PAGE_ID);
    if (!lv || isPageOpen(PAGE_ID)) return false;
    if (isUnlocked(lv)) return lockSession();
    document.documentElement.classList.add("rc-page-locked");
    const card = document.createElement("div");
    card.className = "rc-lock-card";
    const g = grantedLevels();
    if (g.indexOf(lv) === -1) {                       // level not in the student's registration
      card.innerHTML = `<div class="rc-lock-icon">🔒</div>
        <h2>${t(`The ${levelLabel(lv, "en")} level is not part of your registration`, `Le niveau ${levelLabel(lv, "fr")} ne fait pas partie de votre inscription`)}</h2>
        <p>${t("To follow it, please contact me.", "Pour le suivre, merci de me contacter.")}</p>
        <p><a class="rc-continue" href="help.html">${t("Contact me", "Me contacter")}</a>
           <a href="index.html">${t("Back to my dashboard", "Retour à mon tableau de bord")}</a></p>`;
      document.querySelector(".main-container").prepend(card);
      return true;
    }
    const prev = g[g.indexOf(lv) - 1];                // previous level of the registration
    const st = levelStats(prev);
    card.innerHTML = `<div class="rc-lock-icon">🔒</div>
      <h2>${t(`The ${levelLabel(lv, "en")} level is locked`, `Le niveau ${levelLabel(lv, "fr")} est verrouillé`)}</h2>
      <p>${t(`It opens when you complete all quizzes of the <b>${levelLabel(prev, "en")}</b> level with at least <b>${Math.round(PASS * 100)} %</b> of the points.`,
             `Il s'ouvre quand vous avez terminé tous les quiz du niveau <b>${levelLabel(prev, "fr")}</b> avec au moins <b>${Math.round(PASS * 100)} %</b> des points.`)}</p>
      <p>${t("Your current score", "Votre score actuel")} : <b>${Math.round(100 * st.pct)} %</b> ·
         ${t("quizzes done", "quiz faits")} : <b>${st.done}/${st.n}</b></p>
      <p><a class="rc-continue" href="index.html">${t("Back to my dashboard", "Retour à mon tableau de bord")}</a></p>`;
    document.querySelector(".main-container").prepend(card);
    return true;
  }

  // A session of an open level whose previous session is not passed yet
  function lockSession() {
    const f = findPage(PAGE_ID), prev = f.level.pages[f.i - 1], ps = pageStats(prev.id);
    document.documentElement.classList.add("rc-page-locked");
    const card = document.createElement("div");
    card.className = "rc-lock-card";
    card.innerHTML = `<div class="rc-lock-icon">🔒</div>
      <h2>${t("This session is locked", "Cette séance est verrouillée")}</h2>
      <p>${t(`It opens when you finish the quiz of the previous session, <b>${prev.en}</b>, with at least <b>${Math.round(PASS * 100)} %</b> of the points.`,
             `Elle s'ouvre quand vous avez terminé le quiz de la séance précédente, <b>${prev.fr}</b>, avec au moins <b>${Math.round(PASS * 100)} %</b> des points.`)}</p>
      <p>${t("Your score on that session", "Votre score à cette séance")} : <b>${Math.round(100 * ps.pct)} %</b>
         ${ps.n > 1 ? `· ${t("quizzes done", "quiz faits")} : <b>${ps.done}/${ps.n}</b>` : ""}</p>
      <p>${ps.stuck
        ? `<a class="rc-continue" href="help.html?page=${prev.id}">${t("Get help", "Demander de l'aide")}</a>`
        : `<a class="rc-continue" href="${prev.id}.html">${t("Go to the previous session", "Aller à la séance précédente")}</a>`}
         <a href="index.html">${t("My dashboard", "Mon tableau de bord")}</a></p>`;
    document.querySelector(".main-container").prepend(card);
    return true;
  }

  // ::: hint  ...  :::  in the .Rmd  ->  a "Hint" button that shows the text
  function buildHints() {
    document.querySelectorAll("div.hint").forEach((h, k) => {
      const b = document.createElement("button");
      b.className = "rc-hint-btn";
      b.innerHTML = "💡 " + t("Hint", "Indice");
      h.parentNode.insertBefore(b, h);
      b.addEventListener("click", () => h.classList.toggle("show"));
    });
  }

  // Solutions (::: {.solution data-quiz="s01"}) open when the quiz is finished
  function unlockSolutions() {
    document.querySelectorAll(".solution").forEach(sol => {
      const id = sol.dataset.quiz, q = STATE.quizzes[id];
      const open = isTeacher() || quizFinished(q, (QIDX[id] || {}).max || (q && q.max));
      sol.classList.toggle("locked", !open);
      if (!sol.querySelector(".rc-sol-head")) {
        const head = document.createElement("div");
        head.className = "rc-sol-head";
        sol.prepend(head);
        head.addEventListener("click", () => { if (!sol.classList.contains("locked")) sol.classList.toggle("open"); });
      }
      sol.querySelector(".rc-sol-head").innerHTML = open
        ? t("Solution — click to show / hide", "Solution — cliquer pour afficher / masquer")
        : t("Solution (opens when the quiz is finished)", "Solution (s'ouvre quand le quiz est terminé)");
    });
  }

  function addCopyButtons() {
    document.querySelectorAll("pre.r, pre.sourceCode").forEach(pre => {
      if (pre.parentElement.classList.contains("rc-code-wrap")) return;
      const wrap = document.createElement("div");
      wrap.className = "rc-code-wrap";
      pre.parentNode.insertBefore(wrap, pre); wrap.appendChild(pre);
      const b = document.createElement("button");
      b.className = "rc-copy"; b.innerHTML = t("Copy", "Copier");
      b.addEventListener("click", () => {
        navigator.clipboard.writeText(pre.innerText).then(() => {
          b.innerHTML = t("Copied", "Copié"); setTimeout(() => b.innerHTML = t("Copy", "Copier"), 1500);
        });
      });
      wrap.appendChild(b);
    });
  }

  /* --------------------------------------------------------------------------
     PART 9 — Dashboard (index.html: <div id="dashboard">), help page, certificate
     -------------------------------------------------------------------------- */
  function buildDashboard() {
    const box = document.getElementById("dashboard");
    if (!box) return;
    const cont = STATE.lastPage && STATE.lastPage !== "index"
      ? `<a class="rc-continue" href="${STATE.lastPage}.html${STATE.lastSection ? "#" + STATE.lastSection : ""}">
           ${t("Continue where you stopped", "Reprendre là où vous vous êtes arrêté")} →</a>`
      : `<a class="rc-continue" href="${((CFG.levels.find(l => l.id === (isTeacher() ? "beginner" : grantedLevels()[0])) || CFG.levels[0]).pages[0] || {id: "00-kobo-account"}).id}.html">${t("Start the course", "Commencer le cours")} →</a>`;
    let html = `<p class="rc-hello">${t("Hello", "Bonjour")} <b>${AUTH.name}</b></p>${cont}`;
    CFG.levels.forEach(l => {
      const open = isUnlocked(l.id), st = levelStats(l.id);
      let status;
      if (!l.pages.length) status = `<span class="rc-tag soon">${t("coming soon", "bientôt")}</span>`;
      else if (!open) status = grantedLevels().indexOf(l.id) === -1
        ? `<span class="rc-tag locked">🔒 ${t("not in your registration", "hors de votre inscription")}</span> <a href="help.html">${t("contact me", "me contacter")}</a>`
        : `<span class="rc-tag locked">🔒 ${t("opens when the previous level is passed", "s'ouvre quand le niveau précédent est validé")}</span>`;
      else if (l.inProgress && open) status = `<span class="rc-tag open">${t("in preparation", "en préparation")} · ${t("score", "score")} ${Math.round(100 * st.pct)} % · ${st.done}/${st.n} quiz</span>`;
      else if (st.passed) status = `<span class="rc-tag passed">✓ ${t("passed", "validé")} · ${Math.round(100 * st.pct)} %</span>
                                    ${STATE.certificates[l.id] ? `<a href="certificate.html?level=${l.id}">${t("certificate", "certificat")}</a>` : ""}`;
      else if (levelHasStuckPage(l.id) && !isTeacher()) status = `<span class="rc-tag stuck">${t("needs help", "besoin d'aide")}</span> <a href="help.html">${t("contact me", "me contacter")}</a>`;
      else status = `<span class="rc-tag open">${t("score", "score")} ${Math.round(100 * st.pct)} % · ${st.done}/${st.n} quiz</span>`;
      html += `<div class="rc-level ${open ? "" : "is-locked"}"><h3>${t(l.en, l.fr)} ${status}</h3>`;
      if (l.pages.length && open) {
        let rows = "";
        l.pages.forEach(p => {
          const ps = STATE.pages[p.id];
          const pct = ps && ps.total ? Math.round(100 * ps.done.length / ps.total) : 0;
          const ids = p.quizzes || (p.quiz ? [p.quiz] : []);
          let sc = 0, mx = 0, dn = 0;
          ids.forEach(qid => { const q = STATE.quizzes[qid]; if (q) { sc += q.best; mx += q.max; dn++; } });
          const cell = !dn ? "—" : `<b>${sc}/${mx}</b>` + (ids.length > 1 ? ` <small>(${dn}/${ids.length} quiz)</small>` : "");
          const pOpen = isPageOpen(p.id), pst = pageStats(p.id);
          const tag = isSkipped(p.id) ? ` <span class="rc-tag soon">${t("skipped", "dispensé")}</span>`
            : !pOpen ? ` <span class="rc-tag locked">🔒</span>`
            : (pst.complete && pst.passed) ? ` <span class="rc-tag passed">✓</span>`
            : (pst.stuck && !isTeacher() && !manuallyOpenedNext(p.id)) ? ` <a class="rc-tag stuck" href="help.html?page=${p.id}">${t("help", "aide")}</a>` : "";
          const link = pOpen ? `<a href="${p.id}.html">${t(p.en, p.fr)}</a>` : `<span class="rc-locked-row">${t(p.en, p.fr)}</span>`;
          rows += `<tr class="${pOpen ? "" : "is-locked"}"><td>${link}${tag}</td><td>${p.hours} h</td>
            <td><div class="rc-mini"><div style="width:${pct}%"></div></div> ${pct} %</td><td>${cell}</td></tr>`;
        });
        html += `<table class="rc-dash"><thead><tr><th>${t("Session", "Séance")}</th><th>${t("Time", "Durée")}</th>
          <th>${t("Progress", "Progression")}</th><th>${t("Best quiz score", "Meilleur score")}</th></tr></thead><tbody>${rows}</tbody></table>`;
      }
      html += `</div>`;
    });
    box.innerHTML = html;
  }

  function buildHelpPage() {
    const box = document.getElementById("help-box");
    if (!box) return;
    let pageId = new URLSearchParams(location.search).get("page");
    if (!pageId || !findPage(pageId)) {                     // no page given: first stuck session, if any
      const all = CFG.levels.flatMap(l => l.pages.map(p => p.id));
      pageId = all.find(id => isPageOpen(id) && pageStats(id).stuck) || null;
    }
    box.innerHTML = helpMessage(pageId);
  }

  function buildCertificate() {
    const box = document.getElementById("certificate-box");
    if (!box) return;
    const lv = new URLSearchParams(location.search).get("level") || "beginner";
    const c = STATE.certificates[lv];
    if (!c) {
      box.innerHTML = `<p>${t("No certificate yet for this level: it is issued when you pass the level.",
                              "Pas encore de certificat pour ce niveau : il est délivré quand vous validez le niveau.")}</p>`;
      return;
    }
    const l = CFG.levels.find(x => x.id === lv);
    // message + verse of the level (config.js, certificateMessages): on the page only, not printed
    const m = (CFG.certificateMessages || {})[lv];
    const msg = m ? `<div class="rc-cert-msg rc-noprint">${t(m.en, m.fr)}</div>` : "";
    const verse = m && m.verse_en ? `<blockquote class="rc-cert-verse rc-noprint">
        <p>${t(`“${m.verse_en}”`, `« ${m.verse_fr} »`)}</p><footer>${t(m.ref_en, m.ref_fr)}</footer></blockquote>` : "";
    box.innerHTML = `${msg}<div class="rc-cert">
     
      <p class="rc-cert-small">${t("Certificate of completion", "Certificat de réussite")}</p>
      <h1>${t(CFG.title.en, CFG.title.fr)}</h1>
      <p>${t("This certifies that", "Ce certificat atteste que")}</p>
      <p class="rc-cert-name">${AUTH.name}</p>
      <p>${t(`has completed the <b>${l.en}</b> level with a score of <b>${c.pct} %</b>.`,
             `a validé le niveau <b>${l.fr}</b> avec un score de <b>${c.pct} %</b>.`)}</p>
      <div class="rc-cert-foot">
        <div><span class="rc-cert-sign">Aroniaina M. Falinirina</span><br><small>${t("Instructor", "Formateur")}</small></div>
        <div><b>${c.date}</b><br><small>${t("Date", "Date")}</small></div>
        <div><code>${c.code}</code><br><small>${t("Verification code", "Code de vérification")}</small></div>
      </div></div>
      <p class="rc-noprint"><button class="rc-submit" onclick="window.print()">${t("Print / save as PDF", "Imprimer / enregistrer en PDF")}</button></p>
      ${verse}`;
  }

  /* --------------------------------------------------------------------------
     PART 10 — Start-up
     -------------------------------------------------------------------------- */
  function start(fresh) {
    document.documentElement.classList.add("rc-authed");
    applyLang(STATE.lang || currentLang());
    addNavbarExtras();
    const locked = lockPageIfNeeded();
    if (!locked) {
      if (PAGE_ID !== "index" && allPageIds().indexOf(PAGE_ID) !== -1) STATE.lastPage = PAGE_ID;
      buildSections();
      buildQuizzes();
      skippedNote();
      buildHints();
      unlockSolutions();
      addCopyButtons();
    }
    buildDashboard();
    buildHelpPage();
    buildCertificate();
    cacheState();
    if (fresh || PAGE_ID !== "index") saveSoon();
  }

  // Language must be set immediately (before the page is drawn) to avoid flicker
  let lang0 = CFG.defaultLang || "en";
  try { lang0 = localStorage.getItem("kobo_lang") || lang0; } catch (e) {}
  document.documentElement.classList.add("lang-" + lang0);

  document.addEventListener("DOMContentLoaded", function () {
    addWatermark();
    // Certificate preview for the teacher (cert-preview.html): works ONLY on the
    // teacher's own computer (localhost or a file opened from disk), never online.
    if (PAGE_ID === "cert-preview") {
      const box = document.getElementById("certificate-box");
      const local = ["localhost", "127.0.0.1", ""].indexOf(location.hostname) !== -1;
      if (!local) { if (box) box.innerHTML = "<p>Preview available on your own computer only.</p>"; return; }
      AUTH = { user: "preview", name: "<span class=\"en\">Student Name</span><span class=\"fr\">Nom de l'étudiant</span>", level: "advanced", role: "student", openPages: [] };
      STATE = emptyState();
      CFG.levels.forEach(l => { STATE.certificates[l.id] = { code: "RC-PREVIEW-0001", date: new Date().toISOString().slice(0, 10), pct: 88 }; });
      document.documentElement.classList.add("rc-authed");
      buildCertificate();
      return;
    }    
    try { AUTH = JSON.parse(sessionStorage.getItem(AUTH_KEY)); } catch (e) { AUTH = null; }
    if (!AUTH) { showLogin(); return; }
    try { STATE = Object.assign(emptyState(), migrateState(JSON.parse(sessionStorage.getItem("kobo_state_cache")))); }
    catch (e) { STATE = emptyState(); }
    start(false);
  });
})();
