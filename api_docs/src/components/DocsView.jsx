import React from 'react';
import { DOCS_CONTENT, DOCS_SECTIONS } from '../data/docsData';
import CodeBlock from './CodeBlock';
import { Box, Flex, Heading, Text, Button, Card, Separator, Badge, Tabs } from '@radix-ui/themes';
import { ChevronRight, ArrowLeft, ArrowRight, Laptop } from 'lucide-react';

export default function DocsView({ activeSection, onSelectSection }) {
  const doc = DOCS_CONTENT[activeSection] || DOCS_CONTENT['introduction'];

  // Flatten items for pagination
  const allItems = DOCS_SECTIONS.flatMap((cat) => cat.items);
  const currentIndex = allItems.findIndex((item) => item.id === activeSection);
  const prevItem = currentIndex > 0 ? allItems[currentIndex - 1] : null;
  const nextItem = currentIndex < allItems.length - 1 ? allItems[currentIndex + 1] : null;

  const currentCategory = DOCS_SECTIONS.find((cat) =>
    cat.items.some((item) => item.id === activeSection)
  );

  return (
    <Box p="6" style={{ flex: 1, maxWidth: '850px', margin: '0 auto' }}>
      {/* Breadcrumb */}
      <Flex align="center" gap="1" mb="3">
        <Text size="1" color="gray">Docs</Text>
        <ChevronRight size={12} color="var(--gray-8)" />
        <Text size="1" color="gray">{currentCategory?.title || 'Documentation'}</Text>
        <ChevronRight size={12} color="var(--gray-8)" />
        <Text size="1" weight="medium">{doc.title}</Text>
      </Flex>

      {/* Title */}
      <Heading size="8" weight="bold" highContrast mb="2" style={{ letterSpacing: '-0.03em' }}>
        {doc.title}
      </Heading>

      {doc.subtitle && (
        <Text size="3" color="gray" mb="4" as="p" style={{ lineHeight: 1.6 }}>
          {doc.subtitle}
        </Text>
      )}

      <Separator size="4" my="5" />

      {/* Interactive OS Selector for Prerequisites */}
      {activeSection === 'prerequisites' ? (
        <Box my="4">
          <Text size="2" color="gray" mb="4" as="p" style={{ lineHeight: 1.6 }}>
            Zest requires <strong style={{ color: 'var(--gray-12)' }}>Zig 0.16.0</strong> or newer. Because Zest provides universal database drivers for real physical SQLite files and PostgreSQL / Supabase, the standard C development headers for <code style={{ fontFamily: 'monospace', color: 'var(--gray-12)' }}>sqlite3</code> and <code style={{ fontFamily: 'monospace', color: 'var(--gray-12)' }}>libpq</code> must be installed on your development host.
          </Text>

          <Card size="3" variant="surface" my="4">
            <Flex align="center" gap="2" mb="3">
              <Laptop size={18} />
              <Heading size="4">Installing Dependencies by Operating System</Heading>
            </Flex>

            <Tabs.Root defaultValue="ubuntu">
              <Tabs.List>
                <Tabs.Trigger value="ubuntu">Ubuntu / Debian / WSL</Tabs.Trigger>
                <Tabs.Trigger value="macos">macOS (Homebrew)</Tabs.Trigger>
                <Tabs.Trigger value="arch">Arch Linux</Tabs.Trigger>
                <Tabs.Trigger value="fedora">Fedora / RHEL</Tabs.Trigger>
              </Tabs.List>

              <Box pt="3">
                <Tabs.Content value="ubuntu">
                  <Text size="2" color="gray" mb="2" as="p">
                    Run the following command in your terminal to install SQLite 3 and PostgreSQL development headers via apt:
                  </Text>
                  <CodeBlock
                    code="sudo apt-get update && sudo apt-get install -y libsqlite3-dev libpq-dev"
                    language="bash"
                    title="bash"
                  />
                </Tabs.Content>

                <Tabs.Content value="macos">
                  <Text size="2" color="gray" mb="2" as="p">
                    Install SQLite and libpq formulas using Homebrew:
                  </Text>
                  <CodeBlock
                    code="brew install sqlite libpq"
                    language="bash"
                    title="zsh"
                  />
                </Tabs.Content>

                <Tabs.Content value="arch">
                  <Text size="2" color="gray" mb="2" as="p">
                    Install packages using pacman:
                  </Text>
                  <CodeBlock
                    code="sudo pacman -S sqlite postgresql-libs"
                    language="bash"
                    title="bash"
                  />
                </Tabs.Content>

                <Tabs.Content value="fedora">
                  <Text size="2" color="gray" mb="2" as="p">
                    Install development headers using dnf:
                  </Text>
                  <CodeBlock
                    code="sudo dnf install -y sqlite-devel libpq-devel"
                    language="bash"
                    title="bash"
                  />
                </Tabs.Content>
              </Box>
            </Tabs.Root>
          </Card>
        </Box>
      ) : (
        /* General Markdown Content Parser */
        <Box my="4">
          {parseMarkdown(doc.content)}
        </Box>
      )}

      {/* Code Examples */}
      {doc.codeExamples && doc.codeExamples.length > 0 && (
        <Box my="5">
          {doc.codeExamples.map((example, idx) => (
            <CodeBlock
              key={idx}
              code={example.code}
              language={example.language}
              title={example.title}
            />
          ))}
        </Box>
      )}

      <Separator size="4" my="6" />

      {/* Pagination Controls */}
      <Flex justify="between" align="center" my="6">
        {prevItem ? (
          <Button
            size="3"
            variant="surface"
            color="gray"
            onClick={() => onSelectSection(prevItem.id)}
          >
            <ArrowLeft size={15} />
            <Box style={{ textAlign: 'left' }}>
              <Text size="1" color="gray" as="div">Previous</Text>
              <Text size="2" weight="bold">{prevItem.title}</Text>
            </Box>
          </Button>
        ) : <Box />}

        {nextItem && (
          <Button
            size="3"
            variant="surface"
            color="gray"
            onClick={() => onSelectSection(nextItem.id)}
          >
            <Box style={{ textAlign: 'right' }}>
              <Text size="1" color="gray" as="div">Next</Text>
              <Text size="2" weight="bold">{nextItem.title}</Text>
            </Box>
            <ArrowRight size={15} />
          </Button>
        )}
      </Flex>
    </Box>
  );
}

// Line-by-line robust Markdown parser
function parseMarkdown(rawText) {
  if (!rawText) return null;
  const lines = rawText.split('\n');
  const elements = [];
  let i = 0;
  let keyIdx = 0;

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (!trimmed) {
      i++;
      continue;
    }

    // Fenced Code Block
    if (trimmed.startsWith('```')) {
      const lang = trimmed.replace('```', '').trim() || 'text';
      i++;
      const codeLines = [];
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing ```
      elements.push(
        <CodeBlock key={keyIdx++} code={codeLines.join('\n')} language={lang} />
      );
      continue;
    }

    // Headers
    if (trimmed.startsWith('#### ')) {
      elements.push(
        <Heading key={keyIdx++} size="3" weight="bold" highContrast mt="4" mb="2">
          {trimmed.replace('#### ', '')}
        </Heading>
      );
      i++;
      continue;
    }

    if (trimmed.startsWith('### ')) {
      elements.push(
        <Heading key={keyIdx++} size="4" weight="bold" highContrast mt="5" mb="2">
          {trimmed.replace('### ', '')}
        </Heading>
      );
      i++;
      continue;
    }

    if (trimmed.startsWith('## ')) {
      elements.push(
        <Heading key={keyIdx++} size="6" weight="bold" highContrast mt="6" mb="3">
          {trimmed.replace('## ', '')}
        </Heading>
      );
      i++;
      continue;
    }

    // Bullet or Numbered List
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || /^[0-9]+\.\s+/.test(trimmed)) {
      const listItems = [];
      while (i < lines.length && (lines[i].trim().startsWith('- ') || lines[i].trim().startsWith('* ') || /^[0-9]+\.\s+/.test(lines[i].trim()))) {
        const itemText = lines[i].trim().replace(/^[0-9]+\.\s+|^[-*]\s+/, '');
        listItems.push(itemText);
        i++;
      }
      elements.push(
        <Box key={keyIdx++} my="2" pl="3">
          {listItems.map((it, lIdx) => (
            <Flex key={lIdx} align="start" gap="2" my="1">
              <Text color="gray" size="2">•</Text>
              <Text size="2" color="gray" dangerouslySetInnerHTML={{ __html: inlineFormat(it) }} />
            </Flex>
          ))}
        </Box>
      );
      continue;
    }

    // Regular Paragraph
    const paraLines = [];
    while (
      i < lines.length &&
      lines[i].trim() &&
      !lines[i].trim().startsWith('#') &&
      !lines[i].trim().startsWith('```') &&
      !lines[i].trim().startsWith('- ') &&
      !/^[0-9]+\.\s+/.test(lines[i].trim())
    ) {
      paraLines.push(lines[i].trim());
      i++;
    }

    if (paraLines.length > 0) {
      elements.push(
        <Text
          key={keyIdx++}
          as="p"
          size="2"
          color="gray"
          mb="3"
          style={{ lineHeight: 1.7 }}
          dangerouslySetInnerHTML={{ __html: inlineFormat(paraLines.join(' ')) }}
        />
      );
    }
  }

  return elements;
}

function inlineFormat(text) {
  let res = text;
  res = res.replace(/\*\*(.*?)\*\*/g, '<strong style="color:var(--gray-12); font-weight:600;">$1</strong>');
  res = res.replace(/`([^`]+)`/g, '<code style="font-family:monospace; font-size:12px; background:var(--gray-a3); padding:0.15rem 0.35rem; border-radius:4px; color:var(--gray-12);">$1</code>');
  return res;
}
