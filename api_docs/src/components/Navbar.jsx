import React from 'react';
import { Flex, Box, Text, Button, Badge, TextField, Kbd } from '@radix-ui/themes';
import { Search, BookOpen } from 'lucide-react';

function GithubIcon({ size = 15 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4" />
      <path d="M9 18c-4.51 2-5-2-7-2" />
    </svg>
  );
}

export default function Navbar({ currentView, setCurrentView, onOpenSearch, onSelectSection }) {
  return (
    <Box
      py="3"
      px="4"
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 50,
        background: 'var(--color-background)',
        borderBottom: '1px solid var(--gray-a4)',
      }}
    >
      <Flex justify="between" align="center" style={{ maxWidth: '1200px', margin: '0 auto' }}>
        {/* Brand */}
        <Flex align="center" gap="3">
          <Button
            variant="ghost"
            color="gray"
            size="3"
            onClick={() => setCurrentView('landing')}
            style={{ fontWeight: 800, letterSpacing: '-0.02em', fontSize: '18px' }}
          >
            <Box
              style={{
                width: '26px',
                height: '26px',
                borderRadius: '6px',
                background: 'var(--gray-12)',
                color: 'var(--gray-1)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 800,
                fontSize: '13px'
              }}
            >
              Z
            </Box>
            ZEST
          </Button>
          <Badge size="1" variant="soft" color="gray">v0.1.0</Badge>
        </Flex>

        {/* Center Links */}
        <Flex align="center" gap="4">
          <Button
            variant="ghost"
            color={currentView === 'landing' ? 'gray' : 'gray'}
            highContrast={currentView === 'landing'}
            onClick={() => setCurrentView('landing')}
          >
            Overview
          </Button>
          <Button
            variant="ghost"
            color="gray"
            highContrast={currentView === 'docs'}
            onClick={() => {
              setCurrentView('docs');
              onSelectSection('introduction');
            }}
          >
            <BookOpen size={15} />
            Documentation
          </Button>
          <Button
            variant="ghost"
            color="gray"
            onClick={() => {
              setCurrentView('docs');
              onSelectSection('build-zig');
            }}
          >
            build.zig Guide
          </Button>
          <Button
            variant="ghost"
            color="gray"
            onClick={() => {
              setCurrentView('docs');
              onSelectSection('db-architecture');
            }}
          >
            Universal DB
          </Button>
        </Flex>

        {/* Right Search & GitHub */}
        <Flex align="center" gap="3">
          <TextField.Root
            size="2"
            placeholder="Search docs... (Ctrl+K)"
            onClick={onOpenSearch}
            readOnly
            style={{ cursor: 'pointer', minWidth: '180px' }}
          >
            <TextField.Slot>
              <Search size={14} />
            </TextField.Slot>
            <TextField.Slot>
              <Kbd>Ctrl+K</Kbd>
            </TextField.Slot>
          </TextField.Root>

          <Button variant="surface" color="gray" asChild>
            <a href="https://github.com/Alazar42/Zest" target="_blank" rel="noopener noreferrer">
              <GithubIcon size={15} />
              GitHub
            </a>
          </Button>
        </Flex>
      </Flex>
    </Box>
  );
}
