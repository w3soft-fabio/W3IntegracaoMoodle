try {
  const { callMoodle } = await import('./moodle-client.js');

  const courses = await callMoodle('core_course_get_courses', {}, 'GET');

  console.log(`Cursos retornados: ${courses.length}`);

  for (const course of courses) {
    console.log(`${course.id} | ${course.shortname} | ${course.fullname}`);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
