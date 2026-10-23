/* HYPER CLIENT — сайт. Без сборки и зависимостей.
   Разделы: звёздное поле, навигация, живой макет клиента, маршрутизация,
   дорожная карта, релизы с GitHub. */
(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const rand = (lo, hi) => lo + Math.random() * (hi - lo);
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const finePointer = matchMedia("(hover: hover) and (pointer: fine)");

  const REPO = "AnatomikPerq/hp-client";
  // Версия, которая вписана в HTML. Если на GitHub вышла новее, страница
  // подставит её сама; без сети остаётся эта.
  const BAKED_VERSION = "0.1.0-beta.8";

  /* ================= Звёздное поле ================= */

  const Starfield = (() => {
    const canvas = $("#starfield");
    const ctx = canvas.getContext("2d");
    const COOL = [205, 224, 255];
    const CYAN = [122, 216, 245];
    const GOLD = [255, 204, 84];
    let w = 0, h = 0, dpr = 1;
    let stars = [];
    let meteors = [];
    let warm = 0, warmTarget = 0;
    let warpStart = -1, warpDur = 1700;
    let scrollV = 0, lastScroll = scrollY;
    let mx = 0.5, my = 0.5, smx = 0.5, smy = 0.5;
    let nextMeteor = performance.now() + rand(2500, 6000);
    let last = performance.now();
    let running = false;

    function resize() {
      dpr = Math.min(window.devicePixelRatio || 1, 1.75);
      w = innerWidth;
      h = innerHeight;
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const count = Math.round(clamp((w * h) / 2300, 150, 560));
      stars = Array.from({ length: count }, makeStar);
      if (reduceMotion.matches) draw(performance.now(), 0);
    }

    function makeStar() {
      // Больше далёких звёзд, чем близких.
      const z = 0.08 + Math.pow(Math.random(), 2.2) * 0.92;
      return {
        x: Math.random() * w,
        y: Math.random() * h,
        z,
        r: 0.3 + z * 1.25,
        base: 0.35 + Math.random() * 0.65,
        tw: 0.4 + Math.random() * 1.8,
        ph: Math.random() * Math.PI * 2,
        tint: Math.random(),
        sparkle: z > 0.86 && Math.random() < 0.5,
        born: 0,
      };
    }

    const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
    const rgba = (c, a) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a.toFixed(3)})`;
    const wrap = (v, size) => ((v % size) + size) % size;

    function warpLevel(now) {
      if (warpStart < 0) return 0;
      const p = (now - warpStart) / warpDur;
      if (p >= 1) { warpStart = -1; return 0; }
      // Быстрый разгон, плавное торможение.
      return p < 0.25 ? Math.pow(p / 0.25, 2) : Math.pow(1 - (p - 0.25) / 0.75, 1.6);
    }

    function draw(now, dt) {
      ctx.clearRect(0, 0, w, h);
      warm += (warmTarget - warm) * Math.min(1, dt / 900);
      smx += (mx - smx) * Math.min(1, dt / 600);
      smy += (my - smy) * Math.min(1, dt / 600);
      const scroll = scrollY;
      const sv = scrollY - lastScroll;
      lastScroll = scrollY;
      scrollV += (sv - scrollV) * 0.25;
      const wl = warpLevel(now);
      const cx = w / 2, cy = h * 0.42;
      const maxD = Math.hypot(w, h) / 2;

      for (const s of stars) {
        // Медленный дрейф и параллакс: ближние звёзды сдвигаются сильнее.
        s.x -= s.z * 0.004 * dt;
        const px = (smx - 0.5) * -26 * s.z;
        const py = (smy - 0.5) * -16 * s.z - scroll * s.z * 0.14;
        let x = wrap(s.x + px, w);
        let y = wrap(s.y + py, h);

        let dx = 0, dy = 1, len = 0;
        if (wl > 0.001) {
          const ox = x - cx, oy = y - cy;
          const d = Math.hypot(ox, oy) || 1;
          dx = ox / d; dy = oy / d;
          // Скорость в px/мс: дальше от центра и ближе к зрителю — быстрее.
          const v = wl * (0.1 + s.z * 1.1) * (0.2 + d / maxD);
          const nx = x + dx * v * dt, ny = y + dy * v * dt;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) {
            // Улетевшая звезда рождается снова в случайном месте экрана, без
            // хвоста и из прозрачности. Со старым хвостом она прошивала бы
            // экран, оставшись у края — перескакивала бы на другую сторону, а
            // рождаясь только у центра, сбивала бы звёзды в кучу после прыжка.
            s.x += Math.random() * w - x;
            s.y += Math.random() * h - y;
            s.born = now;
          } else {
            s.x += nx - x;
            s.y += ny - y;
            // Хвост зависит от скорости, а не от длины кадра, и не тянется за центр.
            len = Math.min(v * 80, Math.hypot(nx - cx, ny - cy) * 0.9);
          }
          x = wrap(s.x + px, w);
          y = wrap(s.y + py, h);
        } else if (Math.abs(scrollV) > 0.6) {
          dx = 0; dy = Math.sign(scrollV);
          len = Math.min(32, Math.abs(scrollV) * s.z * 0.45);
        }

        const twinkle = 0.72 + 0.28 * Math.sin(now * 0.001 * s.tw + s.ph);
        let fadeIn = 1;
        if (s.born) {
          fadeIn = clamp((now - s.born) / 350, 0, 1);
          if (fadeIn === 1) s.born = 0;
        }
        const alpha = clamp(s.base * twinkle * (0.45 + 0.55 * s.z) * (1 + warm * 0.4 + wl * 0.6), 0, 1) * fadeIn;
        const cool = s.tint < 0.16 ? CYAN : COOL;
        const color = mix(cool, GOLD, clamp(warm * (0.55 + 0.45 * s.tint), 0, 1));

        if (len > 1.2) {
          ctx.strokeStyle = rgba(color, alpha);
          ctx.lineWidth = s.r;
          ctx.beginPath();
          ctx.moveTo(x, y);
          ctx.lineTo(x - dx * len, y - dy * len);
          ctx.stroke();
        } else if (s.sparkle) {
          // Самые яркие звёзды — четырёхлучевые, как на логотипе.
          const k = s.r * (2.6 + 1.6 * twinkle);
          ctx.strokeStyle = rgba(color, alpha * 0.85);
          ctx.lineWidth = 0.7;
          ctx.beginPath();
          ctx.moveTo(x - k, y); ctx.lineTo(x + k, y);
          ctx.moveTo(x, y - k); ctx.lineTo(x, y + k);
          ctx.stroke();
          ctx.fillStyle = rgba(color, alpha);
          ctx.beginPath();
          ctx.arc(x, y, s.r * 0.9, 0, Math.PI * 2);
          ctx.fill();
        } else {
          ctx.fillStyle = rgba(color, alpha);
          const d = s.r * 1.6;
          ctx.fillRect(x - d / 2, y - d / 2, d, d);
        }
      }

      if (!reduceMotion.matches) drawMeteors(now, dt);
    }

    function drawMeteors(now, dt) {
      if (now > nextMeteor) {
        nextMeteor = now + rand(5000, 11000);
        const angle = rand(2.55, 2.8); // вниз и влево
        meteors.push({ x: rand(w * 0.35, w * 1.05), y: rand(-40, h * 0.35), vx: Math.cos(angle), vy: Math.sin(angle), v: rand(0.9, 1.4), len: rand(120, 220), life: 0, max: rand(800, 1200) });
      }
      meteors = meteors.filter((m) => m.life < m.max);
      for (const m of meteors) {
        m.life += dt;
        m.x += m.vx * m.v * dt;
        m.y += m.vy * m.v * dt;
        const fade = Math.sin((m.life / m.max) * Math.PI);
        const color = mix(COOL, GOLD, warm);
        const g = ctx.createLinearGradient(m.x, m.y, m.x - m.vx * m.len, m.y - m.vy * m.len);
        g.addColorStop(0, rgba(color, 0.9 * fade));
        g.addColorStop(1, rgba(color, 0));
        ctx.strokeStyle = g;
        ctx.lineWidth = 1.4;
        ctx.beginPath();
        ctx.moveTo(m.x, m.y);
        ctx.lineTo(m.x - m.vx * m.len, m.y - m.vy * m.len);
        ctx.stroke();
      }
    }

    function frame(now) {
      if (!running) return;
      const dt = Math.min(48, now - last);
      last = now;
      draw(now, dt);
      requestAnimationFrame(frame);
    }

    function start() {
      if (running || reduceMotion.matches || document.hidden) return;
      running = true;
      last = performance.now();
      requestAnimationFrame(frame);
    }
    function stop() { running = false; }

    addEventListener("resize", resize, { passive: true });
    addEventListener("pointermove", (e) => { mx = e.clientX / w; my = e.clientY / h; }, { passive: true });
    document.addEventListener("visibilitychange", () => (document.hidden ? stop() : start()));
    reduceMotion.addEventListener?.("change", () => { stop(); resize(); start(); });

    resize();
    start();

    return {
      setWarm(on) {
        warmTarget = on ? 1 : 0;
        document.documentElement.classList.toggle("warm", on);
        if (reduceMotion.matches) { warm = warmTarget; draw(performance.now(), 0); }
      },
      warp(duration = 1700) {
        if (reduceMotion.matches) return;
        warpDur = duration;
        warpStart = performance.now();
      },
    };
  })();

  /* ================= Навигация ================= */

  const nav = $("#nav");
  const navToggle = $("#nav-toggle");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 12);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  navToggle.addEventListener("click", () => {
    const open = !nav.classList.contains("open");
    nav.classList.toggle("open", open);
    navToggle.setAttribute("aria-expanded", String(open));
  });
  $$("#nav-links a").forEach((a) => a.addEventListener("click", () => {
    nav.classList.remove("open");
    navToggle.setAttribute("aria-expanded", "false");
  }));

  const navLinks = new Map($$("#nav-links a").map((a) => [a.getAttribute("href").slice(1), a]));
  const sectionSpy = new IntersectionObserver((entries) => {
    for (const e of entries) {
      const link = navLinks.get(e.target.id);
      if (link && e.isIntersecting) {
        navLinks.forEach((l) => l.classList.remove("active"));
        link.classList.add("active");
      }
    }
  }, { rootMargin: "-45% 0px -50% 0px" });
  navLinks.forEach((_, id) => { const s = document.getElementById(id); if (s) sectionSpy.observe(s); });

  /* ================= Появление при прокрутке ================= */

  const revealer = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) { e.target.classList.add("in"); revealer.unobserve(e.target); }
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
  $$(".reveal").forEach((el) => revealer.observe(el));

  /* ================= Подсветка карточек под курсором ================= */

  if (finePointer.matches) {
    document.addEventListener("pointermove", (e) => {
      const card = e.target.closest?.(".card");
      if (!card) return;
      const r = card.getBoundingClientRect();
      card.style.setProperty("--mx", `${e.clientX - r.left}px`);
      card.style.setProperty("--my", `${e.clientY - r.top}px`);
    }, { passive: true });
  }

  /* ================= Общее состояние маршрутизации ================= */

  const MODES = {
    smart: {
      pill: "Умная маршрутизация",
      desc: "Выбранные регионы (здесь — Россия) идут напрямую, остальное через VPN. Профили важнее правил режима.",
    },
    selective: {
      pill: "Выборочно",
      desc: "Через VPN только то, что названо во включённых профилях «Через VPN». Всё остальное — напрямую.",
    },
    all: {
      pill: "Всё через VPN",
      desc: "Весь трафик через VPN. Напрямую уходит только то, что названо в профилях «Напрямую».",
    },
  };
  const PROFILES = [
    { id: "ruBlocked", name: "Заблокированное в России", dir: "vpn", on: true },
    { id: "ai", name: "Нейросети", dir: "vpn", on: true },
    { id: "discord", name: "Discord", dir: "vpn", on: false },
    { id: "youtube", name: "YouTube", dir: "vpn", on: false },
    { id: "messengers", name: "Мессенджеры", dir: "vpn", on: false },
    { id: "games", name: "Игры", dir: "direct", on: true },
    { id: "torrents", name: "Торренты", dir: "direct", on: false },
  ];
  const SOURCES = [
    { label: "claude.ai", kind: "site", profiles: ["ai"] },
    { label: "Discord.exe", kind: "app", profiles: ["discord"] },
    { label: "youtube.com", kind: "site", profiles: ["youtube"] },
    { label: "Telegram.exe", kind: "app", profiles: ["messengers"] },
    { label: "instagram.com", kind: "site", profiles: ["ruBlocked"] },
    { label: "steam.exe", kind: "app", profiles: ["games"] },
    { label: "qbittorrent.exe", kind: "app", profiles: ["torrents"] },
    { label: "gosuslugi.ru", kind: "site", profiles: [], ru: true },
    { label: "github.com", kind: "site", profiles: [] },
  ];
  const routing = { mode: "smart", listeners: [] };
  const profileById = new Map(PROFILES.map((p) => [p.id, p]));
  const onRouting = (fn) => routing.listeners.push(fn);
  const emitRouting = () => routing.listeners.forEach((fn) => fn());

  function plural(n, one, few, many) {
    const m10 = n % 10, m100 = n % 100;
    if (m10 === 1 && m100 !== 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }
  function routePillLabel() {
    const n = PROFILES.filter((p) => p.on).length;
    const tail = n ? `${n} ${plural(n, "профиль", "профиля", "профилей")}` : "без профилей";
    return `${MODES[routing.mode].pill} · ${tail}`;
  }

  // Повторяет порядок правил клиента: в «Выборочно» действуют только профили
  // «Через VPN», во «Всё через VPN» — только «Напрямую», в умном — оба, и
  // «Через VPN» важнее.
  function decide(src) {
    const active = src.profiles.map((id) => profileById.get(id)).filter((p) => p && p.on);
    const vpnHit = active.find((p) => p.dir === "vpn");
    const directHit = active.find((p) => p.dir === "direct");
    switch (routing.mode) {
      case "selective":
        return vpnHit ? { to: "vpn", why: `профиль «${vpnHit.name}»` } : { to: "direct", why: "нет во включённых профилях" };
      case "all":
        return directHit && !vpnHit ? { to: "direct", why: `профиль «${directHit.name}»` } : { to: "vpn", why: "всё через VPN" };
      default:
        if (vpnHit) return { to: "vpn", why: `профиль «${vpnHit.name}»` };
        if (directHit) return { to: "direct", why: `профиль «${directHit.name}»` };
        return src.ru ? { to: "direct", why: "регион: Россия" } : { to: "vpn", why: "умный режим: не Россия" };
    }
  }

  /* ================= Живой макет клиента ================= */

  const Demo = (() => {
    const app = $("#app");
    const orb = $("#aw-orb");
    const statusEl = $("#aw-status");
    const toastEl = $("#aw-toast");
    const hint = $("#demo-hint");
    const upEl = $("#aw-up"), downEl = $("#aw-down"), timeEl = $("#aw-time"), totalEl = $("#aw-total");
    const checkRes = $("#aw-check-res");
    const routeLabel = $("#aw-route-label");
    let state = "idle";
    let run = "proxy";
    let pending = 0;
    let ticker = 0;
    let startedAt = 0, upTotal = 0, downTotal = 0, upRate = 0, downRate = 0;
    let toastTimer = 0;

    // Звёзды за орбом, как Starfield в приложении: при подключении теплеют.
    const starsBox = $("#aw-stars");
    for (let i = 0; i < 38; i++) {
      const s = document.createElement("i");
      s.style.left = `${rand(2, 98)}%`;
      s.style.top = `${rand(4, 96)}%`;
      s.style.opacity = rand(0.25, 0.85).toFixed(2);
      if (Math.random() < 0.25) { s.style.width = s.style.height = "3px"; }
      starsBox.appendChild(s);
    }

    function toast(html, ms = 2600) {
      toastEl.innerHTML = html;
      toastEl.classList.add("show");
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => toastEl.classList.remove("show"), ms);
    }

    const fmtRate = (kb) => (kb >= 1024 ? `${(kb / 1024).toFixed(2)} MB/s` : `${kb.toFixed(2)} KB/s`);
    const fmtTotal = (kb) => `${(kb / 1024).toFixed(2)} MB`;
    const pad = (n) => String(n).padStart(2, "0");

    function renderStats() {
      if (state !== "connected") {
        upEl.textContent = "0 B/s";
        downEl.textContent = "0 B/s";
        timeEl.textContent = "00:00";
        totalEl.textContent = "↑ 0 MB · ↓ 0 MB";
        return;
      }
      const sec = Math.floor((Date.now() - startedAt) / 1000);
      timeEl.textContent = sec >= 3600 ? `${Math.floor(sec / 3600)}:${pad(Math.floor(sec / 60) % 60)}:${pad(sec % 60)}` : `${pad(Math.floor(sec / 60))}:${pad(sec % 60)}`;
      upEl.textContent = fmtRate(upRate);
      downEl.textContent = fmtRate(downRate);
      totalEl.textContent = `↑ ${fmtTotal(upTotal)} · ↓ ${fmtTotal(downTotal)}`;
    }

    function tick() {
      // Случайное блуждание вокруг правдоподобной скорости.
      upRate = clamp(upRate + rand(-60, 60), 12, 420);
      downRate = clamp(downRate + rand(-900, 900), 160, 9800);
      upTotal += upRate;
      downTotal += downRate;
      renderStats();
    }

    function setState(next) {
      state = next;
      app.dataset.state = next;
      statusEl.textContent = { idle: "Не подключено", connecting: "Подключение…", connected: "Подключено" }[next];
      orb.setAttribute("aria-label", next === "idle" ? "Подключить (демонстрация)" : "Отключить (демонстрация)");
      clearInterval(ticker);
      if (next === "connected") {
        if (!startedAt) { startedAt = Date.now(); upRate = rand(80, 200); downRate = rand(1500, 4000); }
        ticker = setInterval(tick, 1000);
      } else if (next === "idle") {
        startedAt = 0; upTotal = 0; downTotal = 0;
        checkRes.textContent = "";
      }
      renderStats();
    }

    function connect(delay) {
      clearTimeout(pending);
      setState("connecting");
      pending = setTimeout(() => {
        setState("connected");
        Starfield.setWarm(true);
        Starfield.warp();
      }, delay);
    }

    function disconnect() {
      clearTimeout(pending);
      setState("idle");
      Starfield.setWarm(false);
    }

    orb.addEventListener("click", () => {
      hint.classList.add("hide");
      if (state === "idle") {
        if (run === "tun") toast("TUN: Windows спросит права администратора", 2200);
        connect(run === "tun" ? 1900 : 1300);
      } else if (state === "connecting") {
        // В клиенте ожидание старта тоже можно отменить той же кнопкой.
        disconnect();
        toast("Подключение отменено");
      } else {
        disconnect();
      }
    });

    $$(".aw-seg button").forEach((btn) => btn.addEventListener("click", () => {
      if (btn.dataset.run === run) return;
      run = btn.dataset.run;
      app.dataset.mode = run;
      $$(".aw-seg button").forEach((b) => b.setAttribute("aria-checked", String(b === btn)));
      if (state === "connected") {
        toast(run === "tun" ? "Переподключение в TUN: весь трафик системы" : "Системный прокси: без прав администратора");
        Starfield.setWarm(false);
        connect(run === "tun" ? 1600 : 1000);
      } else {
        toast(run === "tun" ? "TUN заворачивает весь трафик системы" : "Системный прокси обходится без прав администратора", 2200);
      }
    }));

    const rows = $$(".aw-node-row");
    rows.forEach((row) => row.addEventListener("click", () => {
      const prev = rows.find((r) => r.getAttribute("aria-selected") === "true");
      if (prev === row) return;
      rows.forEach((r) => r.setAttribute("aria-selected", String(r === row)));
      $("#aw-node-name").textContent = row.dataset.name;
      $("#aw-node-flag").src = `assets/flags/${row.dataset.flag}.png`;
      $("#aw-node-ping").textContent = `Быстрый · ${row.dataset.ping} мс`;
      checkRes.textContent = "";
      if (state !== "connected") return;
      const city = row.dataset.name.split(" · ")[0];
      // minewire живёт отдельным движком, поэтому смена на него и обратно
      // перезапускает ядро; остальные узлы меняются в работающем ядре.
      const restart = prev && (prev.dataset.tags === "MINEWIRE") !== (row.dataset.tags === "MINEWIRE");
      if (restart) {
        toast("minewire ↔ обычный узел: ядро перезапускается");
        connect(1100);
      } else {
        toast(`Узел сменён на лету: <b>${city}</b>, без переподключения`);
        Starfield.warp(1100);
      }
    }));

    $("#aw-check").addEventListener("click", () => {
      if (state !== "connected") { toast("Сначала подключитесь — орб в центре"); return; }
      checkRes.className = "";
      checkRes.textContent = "…";
      const sel = rows.find((r) => r.getAttribute("aria-selected") === "true");
      const ms = Math.round(Number(sel.dataset.ping) * rand(1.6, 2.6));
      setTimeout(() => { if (state === "connected") checkRes.textContent = `✓ ${ms} мс`; }, rand(500, 900));
    });

    $("#aw-route").addEventListener("click", () => {
      const order = ["smart", "selective", "all"];
      routing.mode = order[(order.indexOf(routing.mode) + 1) % order.length];
      emitRouting();
      toast(`Маршрутизация: <b>${MODES[routing.mode].pill}</b>`);
    });
    onRouting(() => { routeLabel.textContent = routePillLabel(); });

    // Лёгкий наклон окна за курсором.
    const demo = $(".hero-demo");
    if (finePointer.matches && !reduceMotion.matches) {
      demo.addEventListener("pointermove", (e) => {
        const r = demo.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width - 0.5;
        const y = (e.clientY - r.top) / r.height - 0.5;
        app.style.setProperty("--ry", `${(x * 9 - 3).toFixed(2)}deg`);
        app.style.setProperty("--rx", `${(-y * 6 + 1.5).toFixed(2)}deg`);
      });
      demo.addEventListener("pointerleave", () => {
        app.style.removeProperty("--ry");
        app.style.removeProperty("--rx");
      });
    }

    renderStats();
    return { setVersion(v) { $("#aw-ver").textContent = `v${v}`; } };
  })();

  /* ================= «Зачем»: импорт подписки ================= */

  (() => {
    const duel = $("#duel");
    const checkIcon = '<svg class="i"><use href="#i-check"/></svg>';
    $$("li[data-ok] .res", duel).forEach((el) => el.insertAdjacentHTML("afterbegin", checkIcon));

    const play = (instant) => {
      $$(".import-card", duel).forEach((card) => {
        const lines = $$(".import-lines li", card);
        const footer = $("footer", card);
        lines.forEach((li, i) => {
          const show = () => {
            li.classList.add("shown");
            // Обычный клиент выбрасывает непонятные ссылки молча.
            if (li.hasAttribute("data-drop")) setTimeout(() => li.classList.add("gone"), instant ? 0 : 650);
          };
          instant ? show() : setTimeout(show, 260 + i * 300);
        });
        instant ? footer.classList.add("shown") : setTimeout(() => footer.classList.add("shown"), 260 + lines.length * 300 + 700);
      });
    };

    if (reduceMotion.matches) { play(true); return; }
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) { io.disconnect(); play(false); }
    }, { threshold: 0.35 });
    io.observe(duel);
  })();

  /* ================= Визуализации протоколов ================= */

  (() => {
    // minewire: пиксельные блоки идут по «игровой» трубе.
    const pipe = $(".mw-pipe");
    const box = $(".mw-blocks");
    const palette = [
      ["#6abf4b", "#8b5a2b"], ["#57e0c0", "#2f8f7c"], ["#9aa1ab", "#6e747d"],
      ["#6abf4b", "#7a4e26"], ["#e6c86e", "#b8923a"], ["#57e0c0", "#2f8f7c"], ["#9aa1ab", "#5f656e"],
    ];
    const n = palette.length;
    palette.forEach(([c1, c2], i) => {
      const b = document.createElement("i");
      b.style.setProperty("--c1", c1);
      b.style.setProperty("--c2", c2);
      b.style.setProperty("--delay", `${(-(i / n) * 4.4).toFixed(2)}s`);
      box.appendChild(b);
    });
    const sizePipe = () => pipe.style.setProperty("--w", `${pipe.clientWidth + 24}px`);
    sizePipe();
    addEventListener("resize", sizePipe, { passive: true });

    // AmneziaWG: мусор, имитации, рукопожатие с паддингом, данные с заголовками.
    const seq = [
      ["junk", 20], ["junk", 12], ["junk", 28], ["imit", 18], ["imit", 26], ["hs", 58],
      ["data", 40, "#f472b6"], ["data", 30, "#ff9f43"], ["data", 52, "#57e0c0"], ["data", 34, "#c4b5fd"],
      ["data", 46, "#f472b6"], ["junk", 16], ["data", 38, "#ff9f43"], ["data", 28, "#57e0c0"],
    ];
    const html = seq.map(([k, wdt, hcol]) => `<i class="k-${k}" style="width:${wdt}px${hcol ? `;--h:${hcol}` : ""}"></i>`).join("");
    $("#awg-lane").innerHTML = `<div class="awg-strip">${html}${html}</div>`;
  })();

  /* ================= Маршрутизация: интерактивная схема ================= */

  const Router = (() => {
    const profBox = $("#profiles");
    const list = $("#flow-sources");
    const svg = $("#flow-paths");
    const flow = $("#flow");
    const modeDesc = $("#mode-desc");
    const countVpn = $("#count-vpn"), countDirect = $("#count-direct");
    const SVGNS = "http://www.w3.org/2000/svg";
    const icon = (id) => `<svg class="i"><use href="#i-${id}"/></svg>`;
    let links = [];
    let visible = false;
    let drawable = false;
    let looping = false;

    PROFILES.forEach((p) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = `prof ${p.dir}`;
      b.dataset.id = p.id;
      b.setAttribute("aria-pressed", String(p.on));
      b.innerHTML = `<span class="sw" aria-hidden="true"></span><span>${p.name}</span><em>${p.dir === "vpn" ? "через VPN" : "напрямую"}</em>`;
      b.addEventListener("click", () => {
        p.on = !p.on;
        b.setAttribute("aria-pressed", String(p.on));
        emitRouting();
      });
      profBox.appendChild(b);
    });

    $$("#mode-seg button").forEach((b) => b.addEventListener("click", () => {
      routing.mode = b.dataset.mode;
      emitRouting();
    }));

    SOURCES.forEach((s) => {
      const li = document.createElement("li");
      li.className = "src";
      li.innerHTML = `<span class="src-ic">${icon(s.kind === "app" ? "box" : "globe")}</span><span><b>${s.label}</b><small></small></span><span class="to"></span>`;
      list.appendChild(li);
      s.el = li;
    });

    // Пути от источников к двум выходам; точки бегут по ним.
    SOURCES.forEach((s, i) => {
      const path = document.createElementNS(SVGNS, "path");
      const dots = [0, 1].map(() => {
        const c = document.createElementNS(SVGNS, "circle");
        c.setAttribute("r", "2.6");
        c.setAttribute("opacity", "0");
        svg.appendChild(c);
        return c;
      });
      svg.insertBefore(path, svg.firstChild);
      links.push({ src: s, path, dots, y2: null, fromY2: null, toY2: null, t0: 0, phase: (i * 0.137) % 1, len: 0, dest: null });
    });

    function geometry() {
      const fr = flow.getBoundingClientRect();
      const dv = $("#dest-vpn").getBoundingClientRect();
      const dd = $("#dest-direct").getBoundingClientRect();
      return {
        destX: dv.left - fr.left - 4,
        vpnY: dv.top + dv.height / 2 - fr.top,
        directY: dd.top + dd.height / 2 - fr.top,
        fr,
      };
    }

    function pathD(x1, y1, x2, y2) {
      const dx = (x2 - x1) * 0.5;
      return `M${x1},${y1} C${x1 + dx},${y1} ${x2 - dx},${y2} ${x2},${y2}`;
    }

    let geo = null;
    function layout(animate) {
      // На узком экране схемы нет: только список с метками «VPN»/«напрямую».
      drawable = getComputedStyle(svg).display !== "none";
      if (!drawable) return;
      geo = geometry();
      const now = performance.now();
      for (const l of links) {
        const r = l.src.el.getBoundingClientRect();
        l.x1 = r.right - geo.fr.left + 4;
        l.y1 = r.top + r.height / 2 - geo.fr.top;
        const target = l.dest === "vpn" ? geo.vpnY : geo.directY;
        if (animate && l.y2 != null && !reduceMotion.matches) {
          l.fromY2 = l.y2; l.toY2 = target; l.t0 = now;
        } else {
          l.y2 = target; l.toY2 = target; l.t0 = 0;
        }
        l.path.setAttribute("class", l.dest);
        l.dots.forEach((d) => d.setAttribute("class", l.dest));
        l.path.setAttribute("d", pathD(l.x1, l.y1, geo.destX, l.y2));
        l.len = l.path.getTotalLength();
      }
      kick();
    }

    function kick() {
      if (visible && drawable && !looping && !reduceMotion.matches) {
        looping = true;
        requestAnimationFrame(frame);
      }
    }

    function update() {
      modeDesc.textContent = MODES[routing.mode].desc;
      $$("#mode-seg button").forEach((b) => b.setAttribute("aria-checked", String(b.dataset.mode === routing.mode)));
      $$(".prof", profBox).forEach((b) => {
        const p = profileById.get(b.dataset.id);
        // Профили, которые текущий режим не читает, приглушены.
        const inert = (routing.mode === "selective" && p.dir === "direct") || (routing.mode === "all" && p.dir === "vpn");
        b.classList.toggle("inert", inert);
        b.setAttribute("aria-pressed", String(p.on));
      });
      let nv = 0, nd = 0;
      for (const l of links) {
        const d = decide(l.src);
        l.dest = d.to;
        d.to === "vpn" ? nv++ : nd++;
        const el = l.src.el;
        el.classList.toggle("vpn", d.to === "vpn");
        el.classList.toggle("direct", d.to === "direct");
        $("small", el).textContent = d.why;
        $(".to", el).textContent = d.to === "vpn" ? "VPN" : "напрямую";
      }
      bump(countVpn, nv);
      bump(countDirect, nd);
      layout(true);
    }

    function bump(el, value) {
      if (el.textContent === String(value)) return;
      el.textContent = String(value);
      el.classList.remove("bump");
      void el.offsetWidth;
      el.classList.add("bump");
    }

    const ease = (t) => 1 - Math.pow(1 - t, 3);
    function frame(now) {
      if (!visible || !drawable) { looping = false; return; }
      for (const l of links) {
        if (!l.len) continue;
        if (l.t0) {
          const p = Math.min(1, (now - l.t0) / 650);
          l.y2 = l.fromY2 + (l.toY2 - l.fromY2) * ease(p);
          l.path.setAttribute("d", pathD(l.x1, l.y1, geo.destX, l.y2));
          l.len = l.path.getTotalLength();
          if (p >= 1) l.t0 = 0;
        }
        l.dots.forEach((dot, k) => {
          const t = ((now / 2600) + l.phase + k * 0.5) % 1;
          const pt = l.path.getPointAtLength(t * l.len);
          dot.setAttribute("cx", pt.x.toFixed(1));
          dot.setAttribute("cy", pt.y.toFixed(1));
          dot.setAttribute("opacity", Math.sin(t * Math.PI).toFixed(2));
        });
      }
      requestAnimationFrame(frame);
    }

    const io = new IntersectionObserver((entries) => {
      const was = visible;
      visible = entries[0].isIntersecting;
      if (visible && !was) layout(false);
    });
    io.observe(flow);
    addEventListener("resize", () => layout(false), { passive: true });
    document.fonts?.ready.then(() => layout(false));

    onRouting(update);
    return { update };
  })();

  emitRouting();

  /* ================= Дорожная карта: линия прогресса ================= */

  (() => {
    const tl = $("#timeline");
    const onScrollTl = () => {
      const r = tl.getBoundingClientRect();
      const p = clamp((innerHeight * 0.7 - r.top) / r.height, 0, 1);
      tl.style.setProperty("--progress", p.toFixed(3));
    };
    addEventListener("scroll", onScrollTl, { passive: true });
    addEventListener("resize", onScrollTl, { passive: true });
    onScrollTl();
  })();

  /* ================= Копирование ================= */

  $$(".copy").forEach((btn) => btn.addEventListener("click", async () => {
    const text = $(btn.dataset.copy).textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const range = document.createRange();
      range.selectNodeContents($(btn.dataset.copy));
      const sel = getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      document.execCommand?.("copy");
    }
    btn.classList.add("done");
    btn.innerHTML = '<svg class="i"><use href="#i-check"/></svg>';
    setTimeout(() => {
      btn.classList.remove("done");
      btn.innerHTML = '<svg class="i"><use href="#i-copy"/></svg>';
    }, 1600);
  }));

  /* ================= Релизы с GitHub ================= */

  (async () => {
    const CACHE = "hc-releases-v1";
    const fmtSize = (bytes) => `${(bytes / 1048576).toFixed(1).replace(".", ",")} МБ`;
    const fmtDate = (iso) => new Date(iso).toLocaleDateString("ru-RU", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).replace(/\s*г\.?$/, "");
    const short = (v) => (v.match(/(?:alpha|beta|rc)\.\d+$/) || [v])[0];
    const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

    let releases = null;
    try {
      const cached = JSON.parse(sessionStorage.getItem(CACHE) || "null");
      if (cached && Date.now() - cached.at < 10 * 60 * 1000) releases = cached.data;
    } catch { /* хранилище недоступно — просто спросим GitHub */ }

    if (!releases) {
      try {
        const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, { headers: { Accept: "application/vnd.github+json" } });
        if (!res.ok) throw new Error(String(res.status));
        const raw = await res.json();
        releases = raw.filter((r) => !r.draft).map((r) => ({
          tag: r.tag_name, name: r.name, url: r.html_url, date: r.published_at, pre: r.prerelease, body: r.body || "",
          assets: r.assets.map((a) => ({ name: a.name, size: a.size, url: a.browser_download_url, digest: a.digest || "" })),
        }));
        try { sessionStorage.setItem(CACHE, JSON.stringify({ at: Date.now(), data: releases })); } catch { /* не страшно */ }
      } catch {
        return; // Без сети остаются ссылки, вписанные в HTML.
      }
    }
    if (!releases.length) return;

    const latest = releases.find((r) => !r.pre) || releases[0];
    const version = latest.tag.replace(/^v/, "");
    const setup = latest.assets.find((a) => /-setup\.exe$/i.test(a.name));
    const zip = latest.assets.find((a) => /\.zip$/i.test(a.name));
    const hashOf = (a) => {
      if (!a) return "";
      if (a.digest.startsWith("sha256:")) return a.digest.slice(7);
      const m = latest.body.match(new RegExp("`" + a.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "`\\s*\\|\\s*`([0-9a-f]{64})`", "i"));
      return m ? m[1] : "";
    };

    Demo.setVersion(version);
    $("#dl-title").textContent = `HYPER CLIENT ${version}`;
    $("#dl-sub").textContent = `Windows 10 и 11, x64 · выпущен ${fmtDate(latest.date)}`;
    if (setup) {
      $("#hero-download").href = setup.url;
      $("#hero-download-meta").textContent = `${short(version)} · установщик · ${fmtSize(setup.size)}`;
      $("#dl-setup").href = setup.url;
      $("#dl-setup-meta").textContent = `.exe · ${fmtSize(setup.size)} · рекомендуем`;
      $("#hash-cmd").textContent = `Get-FileHash .\\${setup.name}`;
    }
    if (zip) {
      $("#dl-zip").href = zip.url;
      $("#dl-zip-meta").textContent = `.zip · ${fmtSize(zip.size)} · без установки`;
    }
    const hs = hashOf(setup), hz = hashOf(zip);
    if (hs) $("#hash-setup").textContent = hs;
    if (hz) $("#hash-zip").textContent = hz;
    if (!hs && !hz) $("#dl-hashes").hidden = true;

    if (version !== BAKED_VERSION) {
      const news = $("#news");
      news.href = latest.url;
      $("#news-text").textContent = `Вышла ${short(version)} — что нового`;
    }

    $("#older-list").innerHTML = releases.map((r) => {
      const links = r.assets
        .filter((a) => /\.(exe|zip)$/i.test(a.name))
        .map((a) => `<a href="${esc(a.url)}">${/\.exe$/i.test(a.name) ? "setup.exe" : "zip"}</a>`)
        .join("");
      return `<li><a href="${esc(r.url)}">${esc(r.name || r.tag)}</a><span class="od-date">${fmtDate(r.date)}</span><span class="od-links">${links}</span></li>`;
    }).join("");
  })();

  /* ================= Пасхалка: гиперпрыжок ================= */

  $(".wordmark").addEventListener("click", () => Starfield.warp(2200));
  let typed = "";
  addEventListener("keydown", (e) => {
    if (e.target.closest?.("input, textarea, [contenteditable]")) return;
    typed = (typed + e.key.toLowerCase()).slice(-5);
    if (typed === "hyper") Starfield.warp(2400);
  });
})();
