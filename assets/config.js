/* ============================================================================
   config.js  —  THE FILE YOU EDIT TO CONFIGURE THE SITE
   ----------------------------------------------------------------------------
   After editing, rebuild (source("R/build_site.R")) OR edit the copy in
   docs/assets/config.js directly, then commit + push to GitHub.
   ============================================================================ */

window.COURSE_CONFIG = {

  // Course title (login screen) — one per language
  title: { en: "Data collection with KoboToolbox", fr: "Collecte de données avec KoboToolbox" },
  subtitle: { en: "From the questionnaire to the analysis: XLSForm, KoboCollect and R",
              fr: "Du questionnaire à l'analyse : XLSForm, KoboCollect et R" },

  // Name used for the watermark, the footer and the login screen
  author: "Aroo Falinirina",

  // Course version shown in the footer (describe changes in whats-new.Rmd)
  version: "1.0", versionDate: "2026-11",

  // Default language for a first visit: "en" or "fr"
  defaultLang: "fr",

  // Image behind the login card. Replace the file (same name) or change the path,
  // e.g. "assets/img/my-photo.jpg". A wide image (≥ 1600 px) looks best.
  loginBackground: "assets/img/login-bg.svg",

  // Google Apps Script web-app URL. Empty "" = DEMO MODE (accounts below,
  // progress saved only in the browser).
  scriptUrl: "https://script.google.com/macros/s/AKfycbwjo09H_VMB7mX8U50OOuSgDkJ-42sz7hBOy7aRq4n9049UMW1owhBz6AdIYPh5nc8dVg/exec",

  // DEMO MODE only (real accounts are in the Google Sheet, never here: this file is public)
  demoUsers: [
    { user: "demo",    pass: "demo",    name: "Demo Student", level: "beginner", role: "student" },
    { user: "teacher", pass: "teacher", name: "Demo Teacher", level: "advanced", role: "teacher" }
  ],

  // Quiz rules: attempts per quiz, and the share of the level's total points
  // (best attempt of every quiz, practice quizzes included) needed to open the next level.
  maxAttempts: 2,
  passThreshold: 0.75,

  // Message and Bible verse shown on the certificate page of each level
  // (on the page only, not printed on the certificate PDF). Edit freely.
  certificateMessages: {
    beginner: {
      en: "You built, deployed and downloaded your first KoboToolbox forms. Good data start with a good questionnaire: you now have the foundations. Keep going!",
      fr: "Vous avez construit, déployé et téléchargé vos premiers formulaires KoboToolbox. De bonnes données commencent par un bon questionnaire : vous en avez maintenant les bases. Continuez !",
      verse_en: "Not unto us, O LORD, not unto us, but unto thy name give glory, for thy mercy, and for thy truth's sake.",
      ref_en: "Psalm 115:1 (KJV)",
      verse_fr: "Non pas à nous, Éternel, non pas à nous, mais à ton nom donne gloire, à cause de ta bonté, à cause de ta fidélité !",
      ref_fr: "Psaume 115:1 (Louis Segond 1910)"
    },
    intermediate: {
      en: "Congratulations! Your forms now calculate, check and adapt themselves to each answer. Fewer errors in the field means more time for what matters: understanding your data.",
      fr: "Félicitations ! Vos formulaires calculent, contrôlent et s'adaptent maintenant à chaque réponse. Moins d'erreurs sur le terrain, c'est plus de temps pour l'essentiel : comprendre vos données.",
      verse_en: "But by the grace of God I am what I am: and his grace which was bestowed upon me was not in vain; but I laboured more abundantly than they all: yet not I, but the grace of God which was with me.",
      ref_en: "1 Corinthians 15:10 (KJV)",
      verse_fr: "Par la grâce de Dieu je suis ce que je suis, et sa grâce envers moi n'a pas été vaine ; loin de là, j'ai travaillé plus qu'eux tous, non pas moi toutefois, mais la grâce de Dieu qui est avec moi.",
      ref_fr: "1 Corinthiens 15:10 (Louis Segond 1910)"
    },
    advanced: {
      en: "You made it! From the first question to the last table in R, you now master the whole chain of a field survey. This achievement is yours: your patience and hard work made it possible. Keep learning!",
      fr: "Vous y êtes arrivé ! De la première question au dernier tableau dans R, vous maîtrisez maintenant toute la chaîne d'une enquête de terrain. Cette réussite vous appartient : votre patience et votre travail l'ont rendue possible. Continuez d'apprendre !",
      verse_en: "I can do all things through Christ which strengtheneth me.",
      ref_en: "Philippians 4:13 (KJV)",
      verse_fr: "Je puis tout par celui qui me fortifie.",
      ref_fr: "Philippiens 4:13 (Louis Segond 1910)"
    }
  },

  // Shown in the "you need help" message
  contact: { email: "aroo.madaeducation@gmail.com", facebook: "Aroo Falinirina" },

  // Pages that do not belong to a level (never locked)
  extraPages: ["index", "help", "certificate", "cert-preview", "whats-new", "common-errors", "glossary", "downloads",
               "cheatsheet", "cheatsheet-intermediate", "cheatsheet-advanced"],

  // The levels, in order. Each page: id = file name without ".html";
  // quiz / quizzes = quiz id(s) of the page; hours = suggested duration.
  levels: [
    { id: "beginner", en: "Beginner", fr: "Débutant", pages: [
      { id: "00-kobo-account",  quiz: "k00", hours: 1.5, en: "0. KoboToolbox: discover it and create your account", fr: "0. KoboToolbox : le découvrir et créer son compte" },
      { id: "01-formbuilder",   quiz: "k01", hours: 2,   en: "1. Build a form on the platform (Formbuilder)",      fr: "1. Construire un formulaire sur la plateforme" },
      { id: "02-xlsform",       quiz: "k02", hours: 2.5, en: "2. Write a questionnaire in Excel (XLSForm)",         fr: "2. Écrire un questionnaire sous Excel (XLSForm)" },
      { id: "03-multilingual",  quiz: "k03", hours: 1.5, en: "3. Multilingual questionnaires",                       fr: "3. Questionnaire multilingue" },
      { id: "04-deploy",        quiz: "k04", hours: 2.5, en: "4. Import, deploy and collect (web and KoboCollect)",  fr: "4. Importer, déployer et collecter (web et KoboCollect)" },
      { id: "05-download",      quiz: "k05", hours: 2,   en: "5. Look at and download the data",                     fr: "5. Consulter et télécharger les données" },
      { id: "06-practice", quizzes: ["kp1", "kp2", "kp3", "kp4"], hours: 2.5,
                                                         en: "6. Practice session",                                  fr: "6. Séance d'exercices" },
      { id: "07-final-project", quiz: "k07", hours: 3,   en: "7. Final project: octopus gleaning survey",            fr: "7. Projet final : suivi de la pêche à pied du poulpe" }
    ]},
    { id: "intermediate", en: "Intermediate", fr: "Intermédiaire", pages: [
      { id: "i00-calculate",  quiz: "ki0", hours: 2.5, en: "I0. Calculations (calculate)",               fr: "I0. Les calculs (calculate)" },
      { id: "i01-relevant",   quiz: "ki1", hours: 2.5, en: "I1. Conditional display (relevant)",         fr: "I1. L'affichage conditionnel (relevant)" },
      { id: "i02-constraint", quiz: "ki2", hours: 2.5, en: "I2. Input checks (constraint)",              fr: "I2. Les contrôles de saisie (constraint)" },
      { id: "i03-groups",     quiz: "ki3", hours: 2,   en: "I3. Groups of questions (group)",            fr: "I3. Les groupes de questions (group)" },
      { id: "i04-rank",       quiz: "ki4", hours: 1.5, en: "I4. Ranking questions (rank)",               fr: "I4. Les questions de classement (rank)" },
      { id: "i05-repeat",     quiz: "ki5", hours: 3,   en: "I5. Repeats (repeat)",                       fr: "I5. Les répétitions (repeat)" },
      { id: "i06-practice", quizzes: ["kip1", "kip2", "kip3", "kip4"], hours: 2.5,
                                                       en: "I6. Practice session",                       fr: "I6. Séance d'exercices" },
      { id: "i07-final-project", quiz: "ki7", hours: 3.5, en: "I7. Final project: fishers' trip logbook", fr: "I7. Projet final : le carnet des sorties de pêche" }
    ]},
    { id: "advanced", en: "Advanced", fr: "Avancé", pages: [
      { id: "a00-review",        quiz: "ka0", hours: 3,   en: "A0. A complete form, from paper to KoboToolbox", fr: "A0. Un formulaire complet, du papier à KoboToolbox" },
      { id: "a01-choice-filter", quiz: "ka1", hours: 2,   en: "A1. Filtered choice lists (choice_filter)",      fr: "A1. Les listes de choix filtrées (choice_filter)" },
      { id: "a02-cascade",       quiz: "ka2", hours: 2.5, en: "A2. Cascading questions (region › district › commune)", fr: "A2. Les questions en cascade (région › district › commune)" },
      { id: "a03-export",        quiz: "ka3", hours: 2,   en: "A3. Downloading data for analysis",              fr: "A3. Télécharger les données pour l'analyse" },
      { id: "a04-r-import",      quiz: "ka4", hours: 3,   en: "A4. Reading a Kobo export in R: main sheet and groups", fr: "A4. Lire un export Kobo dans R : feuille principale et groupes" },
      { id: "a05-r-repeats",     quiz: "ka5", hours: 3,   en: "A5. Repeat data spread over several sheets, in R", fr: "A5. Les données répétées réparties sur plusieurs feuilles, dans R" },
      { id: "a06-practice", quizzes: ["kap1", "kap2", "kap3", "kap4"], hours: 3,
                                                          en: "A6. Practice session",                           fr: "A6. Séance d'exercices" },
      { id: "a07-final-project", quiz: "ka7", hours: 5,   en: "A7. Final project: complete household survey",   fr: "A7. Projet final : l'enquête ménages complète" }
    ]}
  ]
};
