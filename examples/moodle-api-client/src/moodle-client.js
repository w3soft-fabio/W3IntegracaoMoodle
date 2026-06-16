import { config } from './config.js';

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

function parseMoodleError(body) {
  if (!body || typeof body !== 'object') {
    return null;
  }

  if (body.exception || body.errorcode) {
    return [
      body.errorcode ? `codigo=${body.errorcode}` : null,
      body.exception ? `exception=${body.exception}` : null,
      body.message ? `mensagem=${body.message}` : null
    ]
      .filter(Boolean)
      .join(' | ');
  }

  return null;
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
  let body;

  try {
    body = responseText === '' ? null : JSON.parse(responseText);
  } catch (error) {
    throw new Error(
      `Resposta invalida do Moodle em ${wsfunction}: HTTP ${response.status}. ` +
        `O corpo nao e JSON valido.`
    );
  }

  if (!response.ok) {
    throw new Error(`Falha HTTP ao chamar ${wsfunction}: status ${response.status}.`);
  }

  const moodleError = parseMoodleError(body);

  if (moodleError) {
    throw new Error(`Erro do Moodle ao chamar ${wsfunction}: ${moodleError}`);
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
