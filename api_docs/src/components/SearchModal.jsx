import React, { useState, useEffect } from 'react';
import { Dialog, TextField, Flex, Box, Text, Button, ScrollArea } from '@radix-ui/themes';
import { Search, ChevronRight, FileText, X } from 'lucide-react';
import { DOCS_SECTIONS, DOCS_CONTENT } from '../data/docsData';

export default function SearchModal({ isOpen, onClose, onSelectSection }) {
  const [query, setQuery] = useState('');

  useEffect(() => {
    if (!isOpen) setQuery('');
  }, [isOpen]);

  // Global Ctrl+K trigger
  useEffect(() => {
    const handleKeyDown = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (isOpen) onClose();
        else onClose(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  const results = [];
  const q = query.trim().toLowerCase();

  DOCS_SECTIONS.forEach((cat) => {
    cat.items.forEach((item) => {
      const doc = DOCS_CONTENT[item.id];
      const matchTitle = item.title.toLowerCase().includes(q);
      const matchSubtitle = doc?.subtitle?.toLowerCase().includes(q);
      const matchContent = doc?.content?.toLowerCase().includes(q);

      if (matchTitle || matchSubtitle || matchContent || !q) {
        results.push({
          id: item.id,
          title: item.title,
          category: cat.title,
          subtitle: doc?.subtitle || ''
        });
      }
    });
  });

  return (
    <Dialog.Root open={isOpen} onOpenChange={(open) => { if (!open) onClose(); }}>
      <Dialog.Content size="3" style={{ maxWidth: 540, padding: 0, overflow: 'hidden' }}>
        <Box p="3" style={{ borderBottom: '1px solid var(--gray-a4)' }}>
          <TextField.Root
            size="3"
            placeholder="Search documentation, methods, and models..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            autoFocus
          >
            <TextField.Slot>
              <Search size={16} />
            </TextField.Slot>
            {query && (
              <TextField.Slot>
                <Button size="1" variant="ghost" color="gray" onClick={() => setQuery('')}>
                  <X size={14} />
                </Button>
              </TextField.Slot>
            )}
          </TextField.Root>
        </Box>

        <ScrollArea scrollbars="vertical" style={{ maxHeight: 380, padding: '0.5rem' }}>
          {results.length === 0 ? (
            <Box py="6" style={{ textAlign: 'center' }}>
              <Text size="2" color="gray">No topics found matching "{query}"</Text>
            </Box>
          ) : (
            <Flex direction="column" gap="1">
              {results.map((res) => (
                <Button
                  key={res.id}
                  variant="ghost"
                  color="gray"
                  size="3"
                  onClick={() => {
                    onSelectSection(res.id);
                    onClose();
                  }}
                  style={{
                    justifyContent: 'space-between',
                    padding: '0.75rem',
                    height: 'auto',
                    textAlign: 'left'
                  }}
                >
                  <Flex align="center" gap="3">
                    <FileText size={16} color="var(--gray-9)" />
                    <Box>
                      <Text size="2" weight="bold" as="div">{res.title}</Text>
                      <Text size="1" color="gray">{res.category}</Text>
                    </Box>
                  </Flex>
                  <ChevronRight size={14} color="var(--gray-8)" />
                </Button>
              ))}
            </Flex>
          )}
        </ScrollArea>
      </Dialog.Content>
    </Dialog.Root>
  );
}
