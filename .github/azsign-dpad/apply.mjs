import { readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(process.argv[2] ?? '.');
const base = resolve(root, 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb');
const file = resolve(base, 'InputService.kt');
const source = readFileSync(file, 'utf8');
if (source.includes('AzsignDpadNavigation.handle')) throw new Error('D-pad patch already applied');
const anchor = '                    val possibleNodes = possibleAccessibiltyNodes()';
if (source.split(anchor).length !== 2) throw new Error('Expected exactly one legacy input anchor');
writeFileSync(file, source.replace(anchor,
    '                    if (AzsignDpadNavigation.handle(this@InputService, event)) return@post\n' + anchor));
copyFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'AzsignDpadNavigation.java'),
    resolve(base, 'AzsignDpadNavigation.java'));
