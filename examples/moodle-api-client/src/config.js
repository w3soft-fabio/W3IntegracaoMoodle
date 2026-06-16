import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const currentDir = dirname(fileURLToPath(import.meta.url));
const projectDir = resolve(currentDir, '..');
const envPath = resolve(projectDir, '.env');

function parseEnvValue(value) {
  const trimmed = value.trim();

  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }

  return trimmed;
}

function loadLocalEnv() {
  if (!existsSync(envPath)) {
    return;
  }

  const lines = readFileSync(envPath, 'utf8').split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();

    if (trimmed === '' || trimmed.startsWith('#')) {
      continue;
    }

    const separatorIndex = trimmed.indexOf('=');

    if (separatorIndex === -1) {
      continue;
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    const value = parseEnvValue(trimmed.slice(separatorIndex + 1));

    if (key !== '' && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

function requiredEnv(name) {
  const value = process.env[name];

  if (value === undefined || value.trim() === '') {
    throw new Error(`Variavel de ambiente obrigatoria ausente: ${name}`);
  }

  return value.trim();
}

function optionalEnv(name, defaultValue) {
  const value = process.env[name];

  if (value === undefined || value.trim() === '') {
    return defaultValue;
  }

  return value.trim();
}

function parseIntegerEnv(name, defaultValue) {
  const rawValue = optionalEnv(name, String(defaultValue));
  const value = Number.parseInt(rawValue, 10);

  if (Number.isNaN(value)) {
    throw new Error(`Variavel ${name} precisa ser um numero inteiro.`);
  }

  return value;
}

loadLocalEnv();

export const config = {
  baseUrl: requiredEnv('MOODLE_BASE_URL').replace(/\/+$/, ''),
  token: requiredEnv('MOODLE_WS_TOKEN'),
  defaultCourseId: parseIntegerEnv('MOODLE_DEFAULT_COURSE_ID', 2),
  studentRoleId: parseIntegerEnv('MOODLE_STUDENT_ROLE_ID', 5),
  temporaryPassword: optionalEnv('MOODLE_TEMP_PASSWORD', 'TempPassw0rd!2026'),
  projectDir
};
