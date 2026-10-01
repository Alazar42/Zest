import React, { useState } from 'react';
import Prism from 'prismjs';
import { Card, Flex, Box, Text, Button } from '@radix-ui/themes';
import { Copy, Check, Terminal, FileCode } from 'lucide-react';

// Configure grammars
if (!Prism.languages.zig) {
  Prism.languages.zig = {
    comment: { pattern: /\/\/.*/, greedy: true },
    string: { pattern: /(?:"(?:\\.|[^"\r\n])*"|\\\\.*)/, greedy: true },
    keyword: /\b(?:addrspace|align|allowzero|and|anyerror|anyframe|anytype|asm|async|await|break|callconv|cancel|catch|comptime|const|continue|defer|dynlib|else|enum|errdefer|error|export|extern|fn|for|if|inline|linksection|noalias|noinline|nosuspend|opaque|or|orelse|packed|pub|resume|return|setAlignStack|setCold|setEvalBranchQuota|setFloatMode|setRuntimeSafety|struct|suspend|switch|test|threadlocal|try|union|unreachable|usingnamespace|var|volatile|while)\b/,
    'builtin-type': /\b(?:anyopaque|bool|c_char|c_int|c_long|c_longdouble|c_longlong|c_short|c_uint|c_ulong|c_ulonglong|c_ushort|comptime_float|comptime_int|f128|f16|f32|f64|f80|i128|i16|i32|i64|i8|isize|noreturn|type|u128|u16|u29|u32|u64|u8|usize|void)\b/,
    builtin: /@(?:[a-zA-Z_]\w*)/,
    function: /\b[a-zA-Z_]\w*(?=\s*\()/,
    number: /\b(?:0b[01]+|0o[0-7]+|0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/,
    boolean: /\b(?:true|false)\b/,
    operator: /[-+*\/%!=<>&|^~?:]+/,
    punctuation: /[{}[\];(),.]/,
  };
}

if (!Prism.languages.bash) {
  Prism.languages.bash = {
    comment: { pattern: /(^|[\s#])#.*/, lookbehind: true },
    string: { pattern: /(["'])(?:\\(?:\r\n|[\s\S])|(?!\1)[^\\\r\n])*\1/, greedy: true },
    keyword: /\b(?:if|then|else|elif|fi|for|while|in|do|done|case|esac|function|sudo)\b/,
    function: /\b(?:zig|curl|npm|git|mkdir|cd|rm|cat|grep|echo|npx|apt-get|dnf|pacman|brew)\b/,
    variable: /\$[a-zA-Z_]\w*/,
    operator: /&&|\|\||\||>|<|;/,
    punctuation: /[{}[\];(),.]/,
  };
}

if (!Prism.languages.diff) {
  Prism.languages.diff = {
    coord: /^(@@ -?\d+,\d+ \+\d+,\d+ @@)/m,
    deleted: /^-.*/m,
    inserted: /^\+.*/m,
  };
}

if (!Prism.languages.json) {
  Prism.languages.json = {
    property: { pattern: /"(?:\\.|[^\\"\r\n])*"(?=\s*:)/, greedy: true },
    string: { pattern: /"(?:\\.|[^\\"\r\n])*"/, greedy: true },
    number: /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/,
    punctuation: /[{}[\],:]/,
    boolean: /\b(?:true|false)\b/,
    null: /\bnull\b/,
  };
}

export default function CodeBlock({ code = '', language = 'zig', title = '' }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const langGrammar = Prism.languages[language] || Prism.languages.zig;
  const highlighted = Prism.highlight(code, langGrammar, language);

  return (
    <Card size="2" variant="surface" my="3" style={{ padding: 0, overflow: 'hidden' }}>
      <Flex justify="between" align="center" px="4" py="2" style={{ borderBottom: '1px solid var(--gray-a4)', background: 'var(--gray-a2)' }}>
        <Flex align="center" gap="2">
          {language === 'bash' ? <Terminal size={14} /> : <FileCode size={14} />}
          <Text size="2" weight="medium" color="gray">
            {title || language}
          </Text>
        </Flex>
        <Button size="1" variant="soft" color="gray" onClick={handleCopy}>
          {copied ? <Check size={12} color="var(--green-9)" /> : <Copy size={12} />}
          {copied ? 'Copied' : 'Copy'}
        </Button>
      </Flex>
      <Box p="4" style={{ overflowX: 'auto' }}>
        <pre className={`language-${language}`} style={{ margin: 0, background: 'transparent', padding: 0 }}>
          <code className={`language-${language}`} dangerouslySetInnerHTML={{ __html: highlighted }} />
        </pre>
      </Box>
    </Card>
  );
}
