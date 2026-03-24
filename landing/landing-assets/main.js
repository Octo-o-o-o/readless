/* ============================================================
   Readless Landing Page — Interactions, Theme & i18n
   ============================================================ */
;(function () {
  'use strict'

  /* ── i18n Data ── */
  var i18n = {
    en: {
      // Hero
      'hero.badge': '<span class="hero-badge-dot"></span>macOS app — now available',
      'hero.tagline': 'Turn any long read into a 30\u2011second summary.<br>Or a podcast.',
      'hero.cta': 'Get Started',
      'hero.sub': 'Free for macOS · No account required',

      // Nav
      'nav.download': 'Download',

      // How it works
      'steps.label': 'How it works',
      'steps.title': 'Three steps. Zero friction.',
      'steps.desc': 'Paste a URL, drop a PDF, or capture text from any app. Readless handles the rest.',
      'steps.import.title': 'Import',
      'steps.import.desc': 'Articles, PDFs, images, or text — from any source, in any language.',
      'steps.summarize.title': 'Summarize',
      'steps.summarize.desc': 'AI distills content into four progressive levels of detail — from a one-liner to deep Q&A.',
      'steps.listen.title': 'Listen',
      'steps.listen.desc': 'Generate an AI podcast from any summary. Learn on the go, hands-free.',

      // Features
      'features.label': 'Features',
      'features.title': 'Depth on demand.',
      'features.desc': 'Start with the headline. Drill into the details when you need them.',
      'features.summaries.title': 'Multi-Level Summaries',
      'features.summaries.desc': 'Four layers of understanding, from a glance to a deep dive.',
      'features.summaries.l0': 'L0 — One-liner',
      'features.summaries.l1': 'L1 — Outline',
      'features.summaries.l2': 'L2 — Expanded',
      'features.summaries.l3': 'L3 — Q&A',
      'features.podcast.title': 'AI Podcast',
      'features.podcast.desc': 'Transform any content into a natural-sounding podcast episode. Script generation powered by AI, audio by ElevenLabs.',
      'features.commandbar.title': '⌘K Command Bar',
      'features.commandbar.desc': 'Import URLs, search your library, switch views — all from a single keyboard shortcut. No clicking required.',
      'features.search.title': 'Agentic Search',
      'features.search.desc': 'Ask questions across your entire library. AI parses intent, searches full-text, and synthesizes answers with source citations.',

      // Keyboard
      'keyboard.label': 'Keyboard-first',
      'keyboard.title': 'Your hands never leave the keyboard.',
      'keyboard.desc': 'Navigate, search, and read — all without reaching for the mouse.',
      'keyboard.cmd': 'Command Bar',
      'keyboard.nav': 'Navigate',
      'keyboard.expand': 'Expand',
      'keyboard.search': 'Search',

      // Footer CTA
      'cta.title': 'Read less. Know more.',
      'cta.desc': 'Free for macOS. Get started in seconds.',
      'cta.btn': 'Download for macOS',

      // Footer
      'footer.copy': '© 2026 Readless',

      // Meta
      '_title': 'Readless — Turn any long read into a 30-second summary',
    },
    zh: {
      // Hero
      'hero.badge': '<span class="hero-badge-dot"></span>macOS 应用 — 现已发布',
      'hero.tagline': '将任何长文变成 30 秒摘要。<br>或者，一期播客。',
      'hero.cta': '立即开始',
      'hero.sub': '免费使用 · 无需注册',

      // Nav
      'nav.download': '下载',

      // How it works
      'steps.label': '使用方式',
      'steps.title': '三步完成，零摩擦。',
      'steps.desc': '粘贴链接、拖入 PDF，或从任意应用捕获文本。Readless 处理剩下的一切。',
      'steps.import.title': '导入',
      'steps.import.desc': '文章、PDF、图片或纯文本 — 来源不限，语言不限。',
      'steps.summarize.title': '摘要',
      'steps.summarize.desc': 'AI 将内容提炼为四个渐进层级 — 从一句话概括到深度问答。',
      'steps.listen.title': '收听',
      'steps.listen.desc': '将任意摘要生成 AI 播客。随时随地，解放双手。',

      // Features
      'features.label': '功能',
      'features.title': '深度，按需获取。',
      'features.desc': '从标题开始，需要时再深入细节。',
      'features.summaries.title': '多层级摘要',
      'features.summaries.desc': '四个理解层次，从速览到深度探索。',
      'features.summaries.l0': 'L0 — 一句话',
      'features.summaries.l1': 'L1 — 大纲',
      'features.summaries.l2': 'L2 — 展开',
      'features.summaries.l3': 'L3 — 问答',
      'features.podcast.title': 'AI 播客',
      'features.podcast.desc': '将任何内容转化为自然流畅的播客节目。AI 生成脚本，ElevenLabs 语音合成。',
      'features.commandbar.title': '⌘K 命令栏',
      'features.commandbar.desc': '导入链接、搜索库、切换视图 — 一个快捷键搞定。无需鼠标。',
      'features.search.title': '智能搜索',
      'features.search.desc': '在整个内容库中提问。AI 解析意图、全文检索，综合生成带引用的回答。',

      // Keyboard
      'keyboard.label': '键盘优先',
      'keyboard.title': '双手不离键盘。',
      'keyboard.desc': '导航、搜索、阅读 — 无需触碰鼠标。',
      'keyboard.cmd': '命令栏',
      'keyboard.nav': '导航',
      'keyboard.expand': '展开',
      'keyboard.search': '搜索',

      // Footer CTA
      'cta.title': '少读一点，多知一点。',
      'cta.desc': '免费使用 macOS 版本，秒速上手。',
      'cta.btn': '下载 macOS 版',

      // Footer
      'footer.copy': '© 2026 Readless',

      // Meta
      '_title': 'Readless — 将任何长文变成 30 秒摘要',
    },
  }

  /* ── Theme Management ── */
  var root = document.documentElement
  var themeToggle = document.getElementById('theme-toggle')
  var themeLabel = document.getElementById('theme-label')
  var themeColorMeta = document.querySelector('meta[name="theme-color"]')

  function getTheme() {
    return root.dataset.theme || 'dark'
  }

  function setTheme(theme, save) {
    // Enable transition
    root.classList.add('theme-transitioning')
    root.dataset.theme = theme

    // Update switch state
    themeToggle.classList.toggle('toggle-switch--active', theme === 'light')
    themeToggle.setAttribute('aria-checked', theme === 'light')
    themeLabel.textContent = theme === 'light' ? '🌙' : '☀️'

    // Update meta theme-color
    if (themeColorMeta) {
      themeColorMeta.setAttribute('content', theme === 'light' ? '#ffffff' : '#000000')
    }

    if (save) {
      try { localStorage.setItem('theme', theme) } catch (e) { /* private mode */ }
    }

    // Remove transition class after animation
    setTimeout(function () {
      root.classList.remove('theme-transitioning')
    }, 350)
  }

  // Initialize theme (already set by <head> script, just sync UI)
  setTheme(getTheme(), false)

  // Toggle handler
  themeToggle.addEventListener('click', function () {
    setTheme(getTheme() === 'dark' ? 'light' : 'dark', true)
  })

  // Listen for system theme changes (only when no manual preference)
  var mql = window.matchMedia('(prefers-color-scheme: light)')
  mql.addEventListener('change', function (e) {
    try {
      if (!localStorage.getItem('theme')) {
        setTheme(e.matches ? 'light' : 'dark', false)
      }
    } catch (err) {
      setTheme(e.matches ? 'light' : 'dark', false)
    }
  })

  /* ── Language Management ── */
  var langToggle = document.getElementById('lang-toggle')
  var langLabel = document.getElementById('lang-label')

  function getLang() {
    return root.dataset.lang || 'en'
  }

  function applyLang(lang, save) {
    root.lang = lang
    root.dataset.lang = lang

    // Update switch state
    langToggle.classList.toggle('toggle-switch--active', lang === 'zh')
    langToggle.setAttribute('aria-checked', lang === 'zh')
    langLabel.textContent = lang === 'zh' ? 'EN' : '中'

    // Update text content
    var strings = i18n[lang] || i18n.en

    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n')
      if (strings[key] !== undefined) {
        el.textContent = strings[key]
      }
    })

    document.querySelectorAll('[data-i18n-html]').forEach(function (el) {
      var key = el.getAttribute('data-i18n-html')
      if (strings[key] !== undefined) {
        el.innerHTML = strings[key]
      }
    })

    // Update page title
    if (strings['_title']) {
      document.title = strings['_title']
    }

    if (save) {
      try { localStorage.setItem('lang', lang) } catch (e) { /* private mode */ }
    }
  }

  // Initialize language
  applyLang(getLang(), false)

  // Toggle handler
  langToggle.addEventListener('click', function () {
    applyLang(getLang() === 'en' ? 'zh' : 'en', true)
  })

  /* ── Scroll-triggered fade-in ── */
  var observer = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible')
          observer.unobserve(entry.target)
        }
      })
    },
    { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
  )

  document.querySelectorAll('.fade-in').forEach(function (el) {
    observer.observe(el)
  })

  /* ── Navbar scroll state ── */
  var nav = document.querySelector('.nav')
  var ticking = false

  function onScroll() {
    if (!ticking) {
      requestAnimationFrame(function () {
        nav.classList.toggle('scrolled', window.scrollY > 20)
        ticking = false
      })
      ticking = true
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true })

  /* ── Smooth scroll for anchor links ── */
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      var target = document.querySelector(this.getAttribute('href'))
      if (target) {
        e.preventDefault()
        target.scrollIntoView({ behavior: 'smooth', block: 'start' })
      }
    })
  })

  /* ── Stagger children animation ── */
  document.querySelectorAll('[data-stagger]').forEach(function (parent) {
    var children = parent.children
    var staggerObserver = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            Array.from(children).forEach(function (child, i) {
              child.style.transitionDelay = i * 120 + 'ms'
              child.classList.add('visible')
            })
            staggerObserver.unobserve(entry.target)
          }
        })
      },
      { threshold: 0.1 }
    )
    staggerObserver.observe(parent)
  })
})()
