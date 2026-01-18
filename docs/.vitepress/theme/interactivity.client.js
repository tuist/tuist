/**
 * VitePress MPA Mode Interactivity Fix
 * This script restores interactive functionality that is stripped in MPA mode.
 * It handles sidebar dropdowns, mobile navigation, and search functionality.
 */

(function() {
  'use strict';

  // Wait for DOM to be ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initInteractivity);
  } else {
    initInteractivity();
  }

  function initInteractivity() {
    // Initialize all interactive features
    initSidebar();
    initMobileNavigation();
    initSearch();
    initKeyboardShortcuts();
  }

  // ============================================
  // SIDEBAR DROPDOWNS
  // ============================================

  function initSidebar() {
    const sidebar = document.querySelector('.VPSidebar');
    if (!sidebar) return;

    // Find all collapsible sidebar items
    const collapsibleItems = sidebar.querySelectorAll('.VPSidebarItem.collapsible');

    collapsibleItems.forEach(item => {
      const caret = item.querySelector('.caret');
      const items = item.querySelector('.items');

      if (caret && items) {
        // Make caret clickable
        caret.setAttribute('role', 'button');
        caret.setAttribute('tabindex', '0');
        caret.setAttribute('aria-label', 'toggle section');

        // Add click event listener
        caret.addEventListener('click', (e) => {
          e.preventDefault();
          toggleSidebarItem(item);
        });

        // Add keyboard support
        caret.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            toggleSidebarItem(item);
          }
        });
      }

      // Also make the entire item clickable if it has children
      const itemDiv = item.querySelector('.item');
      if (itemDiv && item.querySelector('.items')) {
        itemDiv.setAttribute('role', 'button');
        itemDiv.setAttribute('tabindex', '0');

        itemDiv.addEventListener('click', (e) => {
          // Only toggle if clicking on the item itself, not on links
          if (!e.target.closest('a')) {
            toggleSidebarItem(item);
          }
        });

        itemDiv.addEventListener('keydown', (e) => {
          if ((e.key === 'Enter' || e.key === ' ') && !e.target.closest('a')) {
            e.preventDefault();
            toggleSidebarItem(item);
          }
        });
      }
    });
  }

  function toggleSidebarItem(item) {
    const isCollapsed = item.classList.contains('collapsed');

    if (isCollapsed) {
      item.classList.remove('collapsed');
      // Save state to localStorage
      saveSidebarState(item, false);
    } else {
      item.classList.add('collapsed');
      // Save state to localStorage
      saveSidebarState(item, true);
    }
  }

  function saveSidebarState(item, collapsed) {
    const textElement = item.querySelector('.text');
    if (!textElement) return;

    const text = textElement.textContent?.trim();
    if (!text) return;

    try {
      const state = JSON.parse(localStorage.getItem('vitepress:sidebar-state') || '{}');
      state[text] = collapsed;
      localStorage.setItem('vitepress:sidebar-state', JSON.stringify(state));
    } catch (e) {
      // Ignore localStorage errors
    }
  }

  function loadSidebarState() {
    try {
      const state = JSON.parse(localStorage.getItem('vitepress:sidebar-state') || '{}');

      Object.entries(state).forEach(([text, collapsed]) => {
        if (collapsed) {
          // Find the sidebar item by text content
          const items = document.querySelectorAll('.VPSidebarItem.collapsible .text');
          items.forEach(item => {
            if (item.textContent?.trim() === text) {
              const sidebarItem = item.closest('.VPSidebarItem');
              if (sidebarItem) {
                sidebarItem.classList.add('collapsed');
              }
            }
          });
        }
      });
    } catch (e) {
      // Ignore localStorage errors
    }
  }

  // ============================================
  // MOBILE NAVIGATION
  // ============================================

  function initMobileNavigation() {
    const hamburger = document.querySelector('.VPNavBarHamburger');
    const navScreen = document.querySelector('.VPNavScreen');

    if (!hamburger || !navScreen) return;

    // Make hamburger button interactive
    hamburger.setAttribute('role', 'button');
    hamburger.setAttribute('aria-label', 'mobile navigation');
    hamburger.setAttribute('aria-expanded', 'false');

    hamburger.addEventListener('click', () => {
      toggleMobileNav(hamburger, navScreen);
    });

    // Keyboard support
    hamburger.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        toggleMobileNav(hamburger, navScreen);
      }
    });

    // Close mobile nav when clicking outside
    document.addEventListener('click', (e) => {
      if (hamburger.classList.contains('active')) {
        if (!hamburger.contains(e.target) && !navScreen.contains(e.target)) {
          closeMobileNav(hamburger, navScreen);
        }
      }
    });

    // Close mobile nav on escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && hamburger.classList.contains('active')) {
        closeMobileNav(hamburger, navScreen);
        hamburger.focus();
      }
    });
  }

  function toggleMobileNav(hamburger, navScreen) {
    if (hamburger.classList.contains('active')) {
      closeMobileNav(hamburger, navScreen);
    } else {
      openMobileNav(hamburger, navScreen);
    }
  }

  function openMobileNav(hamburger, navScreen) {
    hamburger.classList.add('active');
    hamburger.setAttribute('aria-expanded', 'true');
    navScreen.style.display = 'block';
    document.body.classList.add('vp-nav-screen-open');

    // Lock body scroll
    document.body.style.overflow = 'hidden';

    // Focus first focusable element in nav screen
    const firstFocusable = navScreen.querySelector('a, button, [tabindex]');
    if (firstFocusable) {
      firstFocusable.focus();
    }
  }

  function closeMobileNav(hamburger, navScreen) {
    hamburger.classList.remove('active');
    hamburger.setAttribute('aria-expanded', 'false');
    navScreen.style.display = '';
    document.body.classList.remove('vp-nav-screen-open');

    // Unlock body scroll
    document.body.style.overflow = '';
  }

  // ============================================
  // SEARCH FUNCTIONALITY
  // ============================================

  function initSearch() {
    // Handle search button clicks
    const searchButton = document.querySelector('.VPNavBarSearchButton');
    if (searchButton) {
      searchButton.addEventListener('click', (e) => {
        e.preventDefault();
        openSearchModal();
      });
    }

    // Handle Algolia search box if present
    const algoliaSearchBox = document.querySelector('.DocSearch');
    if (algoliaSearchBox) {
      // Algolia should be initialized by their script, but we can add fallback
      console.log('Algolia search detected');
    }
  }

  function openSearchModal() {
    // Try to find and click the search trigger
    const searchButton = document.querySelector('.VPNavBarSearchButton button, .DocSearch-Button');
    if (searchButton) {
      searchButton.click();
    } else {
      // Fallback: trigger keyboard shortcut
      triggerKeyboardShortcut('k');
    }
  }

  // ============================================
  // KEYBOARD SHORTCUTS
  // ============================================

  function initKeyboardShortcuts() {
    document.addEventListener('keydown', handleKeyboardShortcuts);
  }

  function handleKeyboardShortcuts(e) {
    // Ctrl/Cmd + K: Open search
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
      e.preventDefault();
      openSearchModal();
    }

    // Ctrl/Cmd + /: Focus search (alternative)
    if ((e.ctrlKey || e.metaKey) && e.key === '/') {
      e.preventDefault();
      openSearchModal();
    }

    // Escape: Close search modal or mobile nav
    if (e.key === 'Escape') {
      // Close search modal if open
      const searchModal = document.querySelector('.VPLocalSearchBox, .DocSearch-Container');
      if (searchModal) {
        const closeButton = searchModal.querySelector('.VPLocalSearchBox .close, .DocSearch-CloseButton');
        if (closeButton) {
          closeButton.click();
        }
      }
    }
  }

  function triggerKeyboardShortcut(key) {
    const event = new KeyboardEvent('keydown', {
      key: key,
      ctrlKey: true,
      metaKey: false,
      bubbles: true
    });
    document.dispatchEvent(event);
  }

  // ============================================
  // UTILITY FUNCTIONS
  // ============================================

  // Load saved sidebar state on page load
  loadSidebarState();

  // Handle page navigation (for SPA-like behavior where possible)
  document.addEventListener('click', (e) => {
    const link = e.target.closest('a');
    if (link && link.href && link.href.startsWith(window.location.origin)) {
      // Internal link - let VitePress handle it
      return;
    }
  });

})();