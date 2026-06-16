import { createHash } from 'node:crypto';

import { config } from './config.js';

const endpoint = `${config.baseUrl}/webservice/rest/server.php`;
const maxPreviewLength = 900;

function fingerprintSecret(value) {
  return createHash('sha256').update(value).digest('hex').slice(0, 12);
}

function compactWhitespace(value) {
  return value.replace(/\s+/g, ' ').trim();
}

function truncate(value, maxLength = maxPreviewLength) {
  if (value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, maxLength)}...`;
}

function redactSecrets(value) {
  return value
    .replace(/(wstoken=)[^&\s]+/gi, '$1[token oculto]')
    .replaceAll(config.token, '[token oculto]');
}

function stripHtml(value) {
  return compactWhitespace(
    value
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
  );
}

function parseXmlTag(xml, tagName) {
  const match = xml.match(new RegExp(`<${tagName}>([\\s\\S]*?)<\\/${tagName}>`, 'i'));
  return match ? compactWhitespace(match[1]) : null;
}

function summarizeJson(body) {
  if (!body || typeof body !== 'object') {
    return null;
  }

  if (body.exception || body.errorcode || body.message) {
    return [
      body.errorcode ? `codigo=${body.errorcode}` : null,
      body.exception ? `exception=${body.exception}` : null,
      body.message ? `mensagem=${body.message}` : null,
      body.debuginfo ? `debug=${body.debuginfo}` : null
    ]
      .filter(Boolean)
      .join(' | ');
  }

  if (body.username || body.userid || body.sitename) {
    return [
      body.sitename ? `site=${body.sitename}` : null,
      body.username ? `usuario=${body.username}` : null,
      body.userid ? `userid=${body.userid}` : null,
      body.release ? `release=${body.release}` : null
    ]
      .filter(Boolean)
      .join(' | ');
  }

  return truncate(redactSecrets(JSON.stringify(body)));
}

function summarizeBody(responseText, contentType) {
  if (!responseText) {
    return '(corpo vazio)';
  }

  try {
    const parsed = JSON.parse(responseText);
    return summarizeJson(parsed) ?? truncate(redactSecrets(JSON.stringify(parsed)));
  } catch (error) {
    // Continue with XML/HTML/plain text handling.
  }

  const xmlError = responseText.includes('<EXCEPTION')
    ? [
        parseXmlTag(responseText, 'ERRORCODE') ? `codigo=${parseXmlTag(responseText, 'ERRORCODE')}` : null,
        parseXmlTag(responseText, 'MESSAGE') ? `mensagem=${parseXmlTag(responseText, 'MESSAGE')}` : null,
        parseXmlTag(responseText, 'DEBUGINFO') ? `debug=${parseXmlTag(responseText, 'DEBUGINFO')}` : null
      ]
        .filter(Boolean)
        .join(' | ')
    : null;

  if (xmlError) {
    return xmlError;
  }

  const normalizedContentType = contentType.toLowerCase();
  const preview = normalizedContentType.includes('html') ? stripHtml(responseText) : compactWhitespace(responseText);

  return truncate(redactSecrets(preview));
}

function printProbeResult(name, requestUrl, response, responseText) {
  const contentType = response.headers.get('content-type') ?? '(nao informado)';
  const location = response.headers.get('location');
  const server = response.headers.get('server');
  const finalUrl = response.url && response.url !== requestUrl ? response.url : null;

  console.log(`\n## ${name}`);
  console.log(`Status: ${response.status} ${response.statusText || ''}`.trim());
  console.log(`URL testada: ${redactSecrets(requestUrl)}`);

  if (finalUrl) {
    console.log(`URL final: ${redactSecrets(finalUrl)}`);
  }

  console.log(`Content-Type: ${contentType}`);

  if (server) {
    console.log(`Server: ${server}`);
  }

  if (location) {
    console.log(`Location: ${redactSecrets(location)}`);
  }

  console.log(`Resumo: ${summarizeBody(responseText, contentType)}`);
}

async function runProbe({ name, method, url, params }) {
  const requestUrl = method === 'GET' && params ? `${url}?${params.toString()}` : url;
  const requestOptions =
    method === 'POST'
      ? {
          method,
          headers: {
            'content-type': 'application/x-www-form-urlencoded'
          },
          body: params
        }
      : { method };

  try {
    const response = await fetch(requestUrl, requestOptions);
    const responseText = await response.text();
    printProbeResult(name, requestUrl, response, responseText);
  } catch (error) {
    console.log(`\n## ${name}`);
    console.log(`Falha de rede: ${error.message}`);
    console.log(`URL testada: ${redactSecrets(requestUrl)}`);
  }
}

function siteInfoParams(extraParams = {}) {
  return new URLSearchParams({
    wstoken: config.token,
    wsfunction: 'core_webservice_get_site_info',
    moodlewsrestformat: 'json',
    ...extraParams
  });
}

console.log('Diagnostico Moodle Web Service');
console.log(`Base URL: ${config.baseUrl}`);
console.log(`Endpoint REST: ${endpoint}`);
console.log(`Token: presente, ${config.token.length} caracteres, sha256:${fingerprintSecret(config.token)}`);
console.log('O token nao e impresso neste diagnostico.');

await runProbe({
  name: '1. URL base da instituicao',
  method: 'GET',
  url: config.baseUrl
});

await runProbe({
  name: '2. Endpoint REST sem parametros',
  method: 'GET',
  url: endpoint
});

await runProbe({
  name: '3. Endpoint REST com token, sem wsfunction',
  method: 'GET',
  url: endpoint,
  params: new URLSearchParams({
    wstoken: config.token,
    moodlewsrestformat: 'json'
  })
});

await runProbe({
  name: '4. site-info via GET',
  method: 'GET',
  url: endpoint,
  params: siteInfoParams()
});

await runProbe({
  name: '5. site-info via POST',
  method: 'POST',
  url: endpoint,
  params: siteInfoParams()
});
