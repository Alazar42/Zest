import React, { useState } from 'react';
import CodeBlock from './CodeBlock';
import { 
  Container, 
  Flex, 
  Box, 
  Heading, 
  Text, 
  Button, 
  Card, 
  Badge, 
  Grid, 
  Separator 
} from '@radix-ui/themes';
import { 
  ArrowRight, 
  Terminal, 
  Copy, 
  Check, 
  Database, 
  ShieldCheck, 
  Zap, 
  Layers, 
  Clock, 
  Upload, 
  FileCode, 
  Key 
} from 'lucide-react';

const LANDING_CODE = `const std = @import("std");
const zest = @import("zest");

fn welcome(res: *zest.Response) !void {
    try res.json("{\\"message\\": \\"Welcome to Zest API!\\"}");
}

pub fn main() !void {
    var app = zest.init("127.0.0.1", 8000);
    defer app.deinit();

    try app.get("/", welcome);
    try app.serve();
}`;

const FEATURES = [
  {
    icon: Database,
    title: 'Universal Database Engine',
    desc: 'Seamlessly switch between real SQLite files, PostgreSQL / Supabase (libpq), and MongoDB with zero model changes.'
  },
  {
    icon: ShieldCheck,
    title: 'FastAPI-Style Validation',
    desc: 'Declarative struct validation returning automated HTTP 422 Unprocessable Entity structured JSON error payloads.'
  },
  {
    icon: Layers,
    title: 'Model Relationships',
    desc: 'Traverse hasMany and belongsTo associations across relational tables and document collections with compile-time safety.'
  },
  {
    icon: Clock,
    title: 'Background Tasks',
    desc: 'Return instant responses while queueing asynchronous work (emails, audits, webhooks) in background task runners.'
  },
  {
    icon: Upload,
    title: 'Multipart File Uploads',
    desc: 'Native multipart/form-data streaming parser with direct-to-disk file saving via file.saveTo(path).'
  },
  {
    icon: FileCode,
    title: 'Interactive Swagger UI',
    desc: 'Automatic OpenAPI 3.0 specification generation with built-in interactive Swagger UI served at /docs.'
  },
  {
    icon: Zap,
    title: 'Connection Pooling (DbPool)',
    desc: 'Zero-allocation spinlock-protected pool managing active and idle database connections for concurrency.'
  },
  {
    icon: Key,
    title: 'zenv Environment Loader',
    desc: 'Python-like .env configuration parser supporting typed getters (getInt, getBool, getOr) and inline comments.'
  }
];

export default function LandingPage({ onGoToDocs, onSelectSection }) {
  const [copiedInstall, setCopiedInstall] = useState(false);
  const installCmd = 'zig fetch --save git+https://github.com/Alazar42/Zest.git';

  const handleCopyInstall = () => {
    navigator.clipboard.writeText(installCmd);
    setCopiedInstall(true);
    setTimeout(() => setCopiedInstall(false), 2000);
  };

  return (
    <Container size="3" py="8" px="4">
      {/* Hero Section */}
      <Flex direction="column" align="center" gap="4" my="8" style={{ textAlign: 'center' }}>
        <Badge size="2" variant="surface" color="gray" radius="full">
          Zest v0.1.0 Released | Fast, Ergonomic Web Framework for Zig
        </Badge>

        <Heading size="9" weight="bold" highContrast style={{ letterSpacing: '-0.04em', maxWidth: '850px' }}>
          A high-performance, ergonomic web framework for Zig.
        </Heading>

        <Text size="4" color="gray" style={{ maxWidth: '650px', lineHeight: 1.6 }}>
          FastAPI developer ergonomics meet Zig's bare-metal speed, zero-overhead memory safety, and universal database portability.
        </Text>

        {/* Install Command */}
        <Card size="1" variant="surface" my="4">
          <Flex align="center" gap="3" px="2">
            <Terminal size={14} />
            <Text size="2" weight="medium" style={{ fontFamily: 'monospace' }}>
              {installCmd}
            </Text>
            <Button size="1" variant="ghost" color="gray" onClick={handleCopyInstall}>
              {copiedInstall ? <Check size={13} color="var(--green-9)" /> : <Copy size={13} />}
            </Button>
          </Flex>
        </Card>

        {/* Action Buttons */}
        <Flex gap="3" mt="2">
          <Button size="3" variant="solid" color="gray" highContrast onClick={onGoToDocs}>
            Read Documentation <ArrowRight size={16} />
          </Button>
          <Button size="3" variant="soft" color="gray" onClick={() => { onGoToDocs(); onSelectSection('build-zig'); }}>
            build.zig Guide
          </Button>
        </Flex>
      </Flex>

      {/* Landing Code Snippet - Just importing an app, initing, app.get welcome to zest api */}
      <Box my="8" style={{ maxWidth: '750px', margin: '2rem auto' }}>
        <CodeBlock
          code={LANDING_CODE}
          language="zig"
          title="src/main.zig"
        />
      </Box>

      <Separator size="4" my="8" />

      {/* Feature Grid */}
      <Box my="8">
        <Flex direction="column" align="center" gap="2" mb="6" style={{ textAlign: 'center' }}>
          <Heading size="6" weight="bold">
            Built for Modern Web Architecture
          </Heading>
          <Text size="3" color="gray">
            Everything needed to ship production services with zero dependencies.
          </Text>
        </Flex>

        <Grid columns={{ initial: '1', sm: '2', md: '4' }} gap="4">
          {FEATURES.map((feat, i) => {
            const Icon = feat.icon;
            return (
              <Card key={i} size="2" variant="surface">
                <Flex direction="column" gap="2">
                  <Box p="1" style={{ width: 'fit-content' }}>
                    <Icon size={20} />
                  </Box>
                  <Heading size="3" weight="bold">
                    {feat.title}
                  </Heading>
                  <Text size="2" color="gray" style={{ lineHeight: 1.5 }}>
                    {feat.desc}
                  </Text>
                </Flex>
              </Card>
            );
          })}
        </Grid>
      </Box>

      {/* Universal Database Engine Showcase */}
      <Card size="3" variant="classic" my="8">
        <Flex direction="column" gap="4">
          <Box>
            <Badge size="1" variant="soft" color="gray" mb="2">Universal Database</Badge>
            <Heading size="5" weight="bold">One Model Codebase, Multiple Storage Engines</Heading>
            <Text size="2" color="gray" mt="1">
              Switch storage backends simply by editing the connection string in your .env file without rewriting queries or models.
            </Text>
          </Box>

          <Grid columns={{ initial: '1', sm: '3' }} gap="3">
            <Card size="1" variant="surface">
              <Text size="1" color="gray" weight="bold">LOCAL FILE PERSISTENCE</Text>
              <Heading size="3" my="1">SQLite 3</Heading>
              <Text size="1" style={{ fontFamily: 'monospace' }} color="gray">sqlite:data.db</Text>
            </Card>
            <Card size="1" variant="surface">
              <Text size="1" color="gray" weight="bold">PRODUCTION RELATIONAL</Text>
              <Heading size="3" my="1">PostgreSQL / Supabase</Heading>
              <Text size="1" style={{ fontFamily: 'monospace' }} color="gray">postgresql://user:pass@host:5432</Text>
            </Card>
            <Card size="1" variant="surface">
              <Text size="1" color="gray" weight="bold">DOCUMENT STORE</Text>
              <Heading size="3" my="1">MongoDB</Heading>
              <Text size="1" style={{ fontFamily: 'monospace' }} color="gray">mongodb://user:pass@host:27017</Text>
            </Card>
          </Grid>
        </Flex>
      </Card>

      {/* Footer */}
      <Flex direction="column" align="center" gap="2" my="8" pt="6" style={{ borderTop: '1px solid var(--gray-a4)', textAlign: 'center' }}>
        <Flex gap="4">
          <Button variant="ghost" color="gray" size="2" asChild>
            <a href="https://github.com/Alazar42/Zest" target="_blank" rel="noopener noreferrer">GitHub Repository</a>
          </Button>
          <Button variant="ghost" color="gray" size="2" onClick={onGoToDocs}>
            Documentation
          </Button>
          <Button variant="ghost" color="gray" size="2" asChild>
            <a href="https://github.com/Alazar42/Zest/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT License</a>
          </Button>
        </Flex>
        <Text size="2" color="gray">Copyright © 2026 Mickyas Tesfaye. Released under the MIT License.</Text>
      </Flex>
    </Container>
  );
}
