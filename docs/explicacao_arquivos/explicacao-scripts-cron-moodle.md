# Arquivos do cron Moodle

A implementacao atual usa:

- `scripts/moodle-cron-scheduler.sh`: daemon, descoberta, balanceamento, locks e
  execucao do `cron.php`;
- `systemd/moodle-cron-scheduler.service`: supervisao e inicializacao no boot;
- `config/moodle-cron-scheduler.env.example`: configuracao operacional;
- `docs/cron-moodle-systemd.md`: instalacao, testes, operacao e rollback.

Os antigos `run-moodle-crons.sh`, `run-moodle-crons-distributed.sh` e
`config/moodle-cron-tenants.txt` foram removidos. Eles dependiam de uma lista
manual, usavam um agendamento externo e podiam deixar locks obsoletos.

Consulte [cron-moodle-systemd.md](../cron-moodle-systemd.md) para a explicacao
completa.
