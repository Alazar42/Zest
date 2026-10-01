import React, { useState, useEffect, useCallback } from 'react';
import Navbar from './components/Navbar';
import Sidebar from './components/Sidebar';
import DocsView from './components/DocsView';
import LandingPage from './components/LandingPage';
import SearchModal from './components/SearchModal';
import { Box, Flex } from '@radix-ui/themes';
import { DOCS_CONTENT } from './data/docsData';

export default function App() {
  // Parse initial route from URL
  const getInitialState = () => {
    const path = window.location.pathname;
    const hash = window.location.hash.replace('#', '');

    if (path.startsWith('/docs') || hash) {
      const section = hash || 'introduction';
      return {
        view: 'docs',
        section: DOCS_CONTENT[section] ? section : 'introduction'
      };
    }
    return { view: 'landing', section: 'introduction' };
  };

  const initial = getInitialState();
  const [currentView, setCurrentView] = useState(initial.view);
  const [activeSection, setActiveSection] = useState(initial.section);
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  // Sync browser URL
  const updateUrl = useCallback((view, section) => {
    const newUrl = view === 'landing' ? '/' : `/docs#${section}`;
    if (window.location.pathname + window.location.hash !== newUrl) {
      window.history.pushState({ view, section }, '', newUrl);
    }
  }, []);

  // Listen to browser Back / Forward buttons
  useEffect(() => {
    const handlePopState = (e) => {
      if (e.state) {
        setCurrentView(e.state.view || 'landing');
        setActiveSection(e.state.section || 'introduction');
      } else {
        const state = getInitialState();
        setCurrentView(state.view);
        setActiveSection(state.section);
      }
    };

    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  // Scroll to top on section or view change
  useEffect(() => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }, [activeSection, currentView]);

  const handleSelectSection = (sectionId) => {
    const validSection = DOCS_CONTENT[sectionId] ? sectionId : 'introduction';
    setActiveSection(validSection);
    setCurrentView('docs');
    updateUrl('docs', validSection);
  };

  const handleSetView = (view) => {
    setCurrentView(view);
    updateUrl(view, activeSection);
  };

  return (
    <Box style={{ minHeight: '100vh', background: 'var(--color-background)' }}>
      {/* Top Navbar */}
      <Navbar
        currentView={currentView}
        setCurrentView={handleSetView}
        onOpenSearch={() => setIsSearchOpen(true)}
        onSelectSection={handleSelectSection}
      />

      {/* Main Content Area */}
      {currentView === 'landing' ? (
        <LandingPage
          onGoToDocs={() => {
            setCurrentView('docs');
            setActiveSection('introduction');
            updateUrl('docs', 'introduction');
          }}
          onSelectSection={handleSelectSection}
        />
      ) : (
        <Flex style={{ maxWidth: '1200px', margin: '0 auto' }}>
          <Sidebar
            activeSection={activeSection}
            onSelectSection={handleSelectSection}
          />
          <DocsView
            activeSection={activeSection}
            onSelectSection={handleSelectSection}
          />
        </Flex>
      )}

      {/* Global Search Dialog */}
      <SearchModal
        isOpen={isSearchOpen}
        onClose={() => setIsSearchOpen(false)}
        onSelectSection={handleSelectSection}
      />
    </Box>
  );
}
