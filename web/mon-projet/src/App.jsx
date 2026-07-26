import React, { useState } from "react";

const Icon = ({ name, size = 24 }) => {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.9,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    "aria-hidden": true,
  };

  const paths = {
    brain: <><path d="M9.5 4.5A3 3 0 0 0 4 6.2a3.1 3.1 0 0 0 .8 5.8A3 3 0 0 0 8 17.5V20"/><path d="M14.5 4.5A3 3 0 0 1 20 6.2a3.1 3.1 0 0 1-.8 5.8 3 3 0 0 1-3.2 5.5V20"/><path d="M9 8.5a2 2 0 0 0 3 1.7 2 2 0 0 0 3-1.7"/><path d="M12 10v10"/></>,
    file: <><path d="M7 3h7l4 4v14H7z"/><path d="M14 3v5h5"/><path d="M10 13h5M10 17h5"/></>,
    users: <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></>,
    globe: <><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18"/></>,
    wifi: <><path d="M5 12.55a11 11 0 0 1 14 0"/><path d="M8.5 16a6 6 0 0 1 7 0"/><circle cx="12" cy="20" r="1"/></>,
    bot: <><rect x="4" y="6" width="16" height="13" rx="4"/><path d="M12 2v4M8 12h.01M16 12h.01M8 16c2 1 6 1 8 0"/></>,
    game: <><path d="M6 10h12l2 8-3 1-2-3H9l-2 3-3-1z"/><path d="M8 13h4M10 11v4M16 13h.01M18 15h.01"/></>,
    chart: <><path d="M4 19V9M10 19V5M16 19v-7M22 19H2"/></>,
    clipboard: <><rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V2h6v2M8 9h8M8 13h8M8 17h5"/></>,
    clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
    sparkles: <><path d="M12 3l1.3 3.7L17 8l-3.7 1.3L12 13l-1.3-3.7L7 8l3.7-1.3z"/><path d="M19 14l.8 2.2L22 17l-2.2.8L19 20l-.8-2.2L16 17l2.2-.8z"/></>,
    cloud: <><path d="M6 18h11a4 4 0 1 0-.8-7.9A6 6 0 0 0 5 12a3 3 0 0 0 1 6z"/><path d="M9 15l2 2 4-4"/></>,
    download: <><path d="M12 3v12M7 10l5 5 5-5M5 21h14"/></>,
    arrow: <><path d="M5 12h14M14 7l5 5-5 5"/></>,
    menu: <><path d="M4 7h16M4 12h16M4 17h16"/></>,
    close: <><path d="M5 5l14 14M19 5L5 19"/></>,
  };
  return <svg {...common}>{paths[name]}</svg>;
};

const featureStrip = [
  { icon: "brain", title: "Pédagogie adaptative", text: "S’adapte à ton niveau et à ton rythme." },
  { icon: "file", title: "Analyse des copies", text: "Corrections intelligentes et feedback détaillé." },
  { icon: "users", title: "Mode enseignant", text: "Suivi des classes et rapports en temps réel." },
  { icon: "globe", title: "Multilingue", text: "Français, Malagasy et English." },
  { icon: "wifi", title: "Faible connexion", text: "Conçu pour rester accessible partout." },
];

const reasons = [
  { icon: "bot", title: "Tuteur IA personnalisé", text: "Explique les leçons en détail et t’accompagne pas à pas." },
  { icon: "brain", title: "Aide pour les devoirs", text: "Donne des indices et explique les notions sans faire le travail à ta place." },
  { icon: "game", title: "Jeux éducatifs & quiz", text: "Transforme les leçons en activités motivantes et adaptées." },
  { icon: "chart", title: "Suivi intelligent", text: "Identifie tes progrès, tes points faibles et les prochaines étapes." },
  { icon: "users", title: "Mode enseignant", text: "Crée des activités et suis la progression de chaque élève." },
  { icon: "clipboard", title: "Analyse des exercices", text: "Détecte les erreurs et propose des corrections pédagogiques." },
];

const stats = [
  { icon: "globe", value: "3", label: "langues", text: "Français, Malagasy et English" },
  { icon: "clock", value: "24/7", label: "Disponible", text: "Apprends à tout moment." },
  { icon: "sparkles", value: "Adaptatif", label: "À ton rythme", text: "Un parcours ajusté à tes objectifs." },
  { icon: "cloud", value: "Offline-friendly", label: "Faible connexion", text: "Pensé pour les réalités locales." },
];

function App() {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <main>
      <header className="navbar">
        <a className="brand" href="#accueil" aria-label="Gemma Edu, accueil">
          <img src="/assets/logo-mark.png" alt="" />
          <span><strong>Gemma Edu</strong><small>Ton compagnon d’apprentissage intelligent</small></span>
        </a>

        <button className="menu-button" onClick={() => setMenuOpen(!menuOpen)} aria-label="Ouvrir le menu">
          <Icon name={menuOpen ? "close" : "menu"} />
        </button>

        <nav className={menuOpen ? "nav-links open" : "nav-links"}>
          <a href="#accueil" onClick={() => setMenuOpen(false)}>Accueil</a>
          <a href="#fonctionnalites" onClick={() => setMenuOpen(false)}>Fonctionnalités</a>
          <a href="#eleves" onClick={() => setMenuOpen(false)}>Élèves</a>
          <a href="#professeurs" onClick={() => setMenuOpen(false)}>Professeurs</a>
          <a href="#telecharger" onClick={() => setMenuOpen(false)}>Télécharger</a>
          <a href="#contact" onClick={() => setMenuOpen(false)}>Contact</a>
        </nav>

        <div className="nav-actions">
          <a className="btn btn-outline" href="#connexion">Se connecter</a>
          <a className="btn btn-primary" href="#inscription">S’inscrire</a>
        </div>
      </header>

      <section className="hero" id="accueil">
        <div className="hero-copy">
          <span className="eyebrow">Éducation localisée • Propulsée par Gemma</span>
          <h1>L’apprentissage <em>intelligent,</em><br />à ton rythme.</h1>
          <p>
            Gemma Edu est ton assistant IA éducatif. Il explique les leçons, aide avec les devoirs,
            analyse les copies et accompagne chaque apprenant étape par étape, en français, malagasy et anglais.
          </p>
          <div className="hero-buttons">
            <a className="btn btn-primary btn-large" href="#inscription">Commencer maintenant <Icon name="arrow" size={20} /></a>
            <a className="btn btn-outline btn-large" href="#fonctionnalites">Découvrir la démo <span className="play">▶</span></a>
          </div>

          <div className="download-card" id="telecharger">
            <img src="/assets/qr-download.png" alt="QR code de téléchargement Gemma Edu" />
            <div>
              <strong>Scanner pour télécharger l’application</strong>
              <a href="https://gemmaedu.app/download">gemmaedu.app/download ↗</a>
            </div>
          </div>
        </div>

        <div className="phone-stage" aria-label="Aperçu de l’application mobile Gemma Edu">
          <span className="orb orb-one"></span><span className="orb orb-two"></span>
          <div className="phone phone-left">
            <div className="phone-speaker"></div>
            <img src="/assets/phone-home.png" alt="Écran d’accueil mobile Gemma Edu" />
          </div>
          <div className="phone phone-right">
            <div className="phone-speaker"></div>
            <img src="/assets/phone-result.png" alt="Écran de résultat mobile Gemma Edu" />
          </div>
        </div>
      </section>

      <section className="feature-strip" id="fonctionnalites">
        {featureStrip.map((item) => (
          <article key={item.title}>
            <span className="icon-bubble"><Icon name={item.icon} /></span>
            <div><h3>{item.title}</h3><p>{item.text}</p></div>
          </article>
        ))}
      </section>

      <section className="reasons section" id="eleves">
        <div className="section-heading">
          <span>Une solution pédagogique complète</span>
          <h2>Pourquoi choisir <em>Gemma Edu</em> ?</h2>
          <p>Une expérience simple, humaine et inclusive pour apprendre, enseigner et progresser.</p>
        </div>
        <div className="reason-grid">
          {reasons.map((item) => (
            <article className="reason-card" key={item.title}>
              <span className="icon-bubble big"><Icon name={item.icon} size={30} /></span>
              <h3>{item.title}</h3>
              <p>{item.text}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="stats-section section" id="professeurs">
        <div className="section-heading compact">
          <h2>Une solution de confiance, conçue pour l’impact</h2>
        </div>
        <div className="stats-grid">
          {stats.map((item) => (
            <article className="stat-card" key={item.value}>
              <span className="icon-bubble"><Icon name={item.icon} /></span>
              <div><strong>{item.value}</strong><b>{item.label}</b><p>{item.text}</p></div>
            </article>
          ))}
        </div>
      </section>

      <section className="cta" id="inscription">
        <div>
          <span>Prêt à commencer ?</span>
          <h2>Transforme ta façon d’apprendre.</h2>
          <p>Rejoins Gemma Edu et bénéficie d’un accompagnement pédagogique intelligent, localisé et accessible.</p>
        </div>
        <div className="cta-actions">
          <a className="btn btn-white btn-large" href="#telecharger"><Icon name="download" size={20} /> Télécharger l’application</a>
          <a className="cta-link" href="#connexion">Commencer maintenant <Icon name="arrow" size={18} /></a>
        </div>
      </section>

      <footer id="contact">
        <div className="brand footer-brand">
          <img src="/assets/logo-mark.png" alt="" />
          <span><strong>Gemma Edu</strong><small>L’éducation intelligente, accessible à tous.</small></span>
        </div>
        <p>© 2026 Gemma Edu. Tous droits réservés.</p>
      </footer>
    </main>
  );
}

export default App;