import React from 'react';
import { DOCS_SECTIONS } from '../data/docsData';
import { Box, Flex, Text, Button, ScrollArea } from '@radix-ui/themes';
import { BookOpen, Globe, Database, Layers, Sparkles, Server, Shield } from 'lucide-react';

const CATEGORY_ICONS = {
  'getting-started': BookOpen,
  'routing-http': Globe,
  'database-engine': Database,
  'orm-models': Layers,
  'advanced-features': Sparkles,
  'production-deployment': Server,
};

export default function Sidebar({ activeSection, onSelectSection }) {
  return (
    <Box
      style={{
        width: '260px',
        height: 'calc(100vh - 60px)',
        position: 'sticky',
        top: '60px',
        borderRight: '1px solid var(--gray-a4)',
      }}
    >
      <ScrollArea scrollbars="vertical" style={{ height: '100%', padding: '1.25rem 0.75rem' }}>
        <Flex direction="column" gap="5">
          {DOCS_SECTIONS.map((category) => {
            const Icon = CATEGORY_ICONS[category.id] || BookOpen;
            return (
              <Box key={category.id}>
                <Flex align="center" gap="2" px="2" mb="2">
                  <Icon size={13} color="var(--gray-9)" />
                  <Text size="1" weight="bold" color="gray" style={{ textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                    {category.title}
                  </Text>
                </Flex>

                <Flex direction="column" gap="1">
                  {category.items.map((item) => {
                    const isActive = activeSection === item.id;
                    return (
                      <Button
                        key={item.id}
                        size="2"
                        variant={isActive ? 'soft' : 'ghost'}
                        color="gray"
                        highContrast={isActive}
                        onClick={() => onSelectSection(item.id)}
                        style={{
                          justifyContent: 'flex-start',
                          textAlign: 'left',
                          fontWeight: isActive ? 600 : 400,
                        }}
                      >
                        {item.title}
                      </Button>
                    );
                  })}
                </Flex>
              </Box>
            );
          })}
        </Flex>
      </ScrollArea>
    </Box>
  );
}
