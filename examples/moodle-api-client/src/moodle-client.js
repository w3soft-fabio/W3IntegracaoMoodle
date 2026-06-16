import { config } from './config.js';

const MAX_RESPONSE_PREVIEW_LENGTH = 1200;

function appendParam(params, key, value) {
  if (value === undefined || value === null) {
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((item, index) => appendParam(params, `${key}[${index}]`, item));
    return;
  }

  if (typeof value === 'object') {
    Object.entries(value).forEach(([childKey, childValue]) => {
      appendParam(params, `${key}[${childKey}]`, childValue);
    });
    return;
  }

  params.append(key, String(value));
}

function buildParams(wsfunction, params = {}) {
  const requestParams = new URLSearchParams({
    wstoken: config.token,
    wsfunction,
    moodlewsrestformat: 'json'
  });

  Object.entries(params).forEach(([key, value]) => appendParam(requestParams, key, value));

  return requestParams;
}

function truncate(value, maxLength = MAX_RESPONSE_PREVIEW_LENGTH) {
  if (value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, maxLength)}...`;
}

function compactWhitespace(value) {
  return value.replace(/\s+/g, ' ').trim();
}

function stripHtml(value) {
  return compactWhitespace(
    value
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
  );
}

function parseMoodleError(body) {
  if (!body || typeof body !== 'object') {
    return null;
  }

  if (body.exception || body.errorcode) {
    return [
      body.errorcode ? `codigo=${body.errorcode}` : null,
      body.exception ? `exception=${body.exception}` : null,
      body.message ? `mensagem=${body.message}` : null,
      body.debuginfo ? `debug=${body.debuginfo}` : null
    ]
      .filter(Boolean)
      .join(' | ');
  }

  return null;
}

function parseXmlTag(xml, tagName) {
  const match = xml.match(new RegExp(`<${tagName}>([\\s\\S]*?)<\\/${tagName}>`, 'i'));
  return match ? compactWhitespace(match[1]) : null;
}

function parseMoodleXmlError(responseText) {
  if (!responseText || !responseText.includes('<EXCEPTION')) {
    return null;
  }

  return [
    parseXmlTag(responseText, 'ERRORCODE')
      ? `codigo=${parseXmlTag(responseText, 'ERRORCODE')}`
      : null,
    parseXmlTag(responseText, 'MESSAGE')
      ? `mensagem=${parseXmlTag(responseText, 'MESSAGE')}`
      : null,
    parseXmlTag(responseText, 'DEBUGINFO')
      ? `debug=${parseXmlTag(responseText, 'DEBUGINFO')}`
      : null
  ]
    .filter(Boolean)
    .join(' | ');
}

function summarizeResponseBody(responseText, contentType) {
  if (!responseText) {
    return '(corpo vazio)';
  }

  const normalizedContentType = contentType.toLowerCase();
  const preview = normalizedContentType.includes('html') ? stripHtml(responseText) : compactWhitespace(responseText);

  return truncate(preview);
}

function buildRequestError({ wsfunction, method, endpoint, response, contentType, details, responseText }) {
  return [
    `Erro ao chamar ${wsfunction}.`,
    `HTTP status: ${response.status} ${response.statusText || ''}`.trim(),
    `Metodo: ${method}`,
    `Endpoint: ${endpoint}`,
    `Content-Type: ${contentType}`,
    details ? `Detalhes: ${details}` : null,
    responseText ? `Corpo da resposta: ${summarizeResponseBody(responseText, contentType)}` : null
  ]
    .filter(Boolean)
    .join('\n');
}

export async function callMoodle(wsfunction, params = {}, method = 'POST') {
  const normalizedMethod = method.toUpperCase();
  const requestParams = buildParams(wsfunction, params);
  const endpoint = `${config.baseUrl}/webservice/rest/server.php`;
  const request =
    normalizedMethod === 'GET'
      ? new Request(`${endpoint}?${requestParams.toString()}`, { method: 'GET' })
      : new Request(endpoint, {
          method: 'POST',
          headers: {
            'content-type': 'application/x-www-form-urlencoded'
          },
          body: requestParams
        });

  const response = await fetch(request);
  const responseText = await response.text();
  const contentType = response.headers.get('content-type') ?? '(nao informado)';
  let body;

  try {
    body = responseText === '' ? null : JSON.parse(responseText);
  } catch (error) {
    const xmlError = parseMoodleXmlError(responseText);

    throw new Error(
      buildRequestError({
        wsfunction,
        method: normalizedMethod,
        endpoint,
        response,
        contentType,
        details: xmlError ?? 'O corpo nao e JSON valido.',
        responseText
      })
    );
  }

  const moodleError = parseMoodleError(body) ?? parseMoodleXmlError(responseText);

  if (moodleError) {
    throw new Error(
      buildRequestError({
        wsfunction,
        method: normalizedMethod,
        endpoint,
        response,
        contentType,
        details: moodleError,
        responseText
      })
    );
  }

  if (!response.ok) {
    throw new Error(
      buildRequestError({
        wsfunction,
        method: normalizedMethod,
        endpoint,
        response,
        contentType,
        responseText
      })
    );
  }

  return body;
}

export async function getUserByUsername(username) {
  const users = await callMoodle('core_user_get_users_by_field', {
    field: 'username',
    values: [username]
  });

  return users[0] ?? null;
}

export async function createUser(student) {
  const users = await callMoodle('core_user_create_users', {
    users: [
      {
        username: student.username,
        password: config.temporaryPassword,
        firstname: student.firstname,
        lastname: student.lastname,
        email: student.email,
        idnumber: student.idnumber,
        city: student.city,
        country: student.country
      }
    ]
  });

  return users[0];
}

export async function enrolUser(userid) {
  return callMoodle('enrol_manual_enrol_users', {
    enrolments: [
      {
        roleid: config.studentRoleId,
        userid,
        courseid: config.defaultCourseId
      }
    ]
  });
}
