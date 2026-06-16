try {
  const { config } = await import('./config.js');
  const { callMoodle } = await import('./moodle-client.js');

  const siteInfo = await callMoodle('core_webservice_get_site_info', {}, 'GET');

  console.log('Conexao com Moodle validada.');
  console.log(`URL base: ${config.baseUrl}`);
  console.log(`Site: ${siteInfo.sitename ?? '(sem nome retornado)'}`);
  console.log(`Usuario do token: ${siteInfo.username ?? siteInfo.fullname ?? '(nao informado)'}`);
  console.log(`Versao Moodle: ${siteInfo.release ?? '(nao informada)'}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
