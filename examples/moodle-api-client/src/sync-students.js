import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

try {
  const { config } = await import('./config.js');
  const { createUser, enrolUser, getUserByUsername } = await import('./moodle-client.js');

  const studentsPath = resolve(config.projectDir, 'students.mock.json');
  const students = JSON.parse(readFileSync(studentsPath, 'utf8'));

  console.log(`Sincronizando ${students.length} alunos no curso ${config.defaultCourseId}.`);

  for (const student of students) {
    const existingUser = await getUserByUsername(student.username);
    const user = existingUser ?? (await createUser(student));
    const action = existingUser ? 'existente' : 'criado';

    await enrolUser(user.id);

    console.log(
      `${student.username}: usuario ${action}, id ${user.id}, matricula solicitada no curso ${config.defaultCourseId}.`
    );
  }

  console.log('Sincronizacao concluida.');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
