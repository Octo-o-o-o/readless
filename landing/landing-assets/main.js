/* ============================================================
   Readless Landing Page — Interactions
   ============================================================ */
;(function () {
  'use strict'

  /* ── Scroll-triggered fade-in ── */
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible')
          observer.unobserve(entry.target)
        }
      })
    },
    { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
  )

  document.querySelectorAll('.fade-in').forEach((el) => observer.observe(el))

  /* ── Navbar scroll state ── */
  const nav = document.querySelector('.nav')
  let ticking = false

  function onScroll() {
    if (!ticking) {
      requestAnimationFrame(() => {
        nav.classList.toggle('scrolled', window.scrollY > 20)
        ticking = false
      })
      ticking = true
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true })

  /* ── Smooth scroll for anchor links ── */
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', function (e) {
      const target = document.querySelector(this.getAttribute('href'))
      if (target) {
        e.preventDefault()
        target.scrollIntoView({ behavior: 'smooth', block: 'start' })
      }
    })
  })

  /* ── Stagger children animation ── */
  document.querySelectorAll('[data-stagger]').forEach((parent) => {
    const children = parent.children
    const staggerObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            Array.from(children).forEach((child, i) => {
              child.style.transitionDelay = `${i * 120}ms`
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
