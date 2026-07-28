# Passo 08: cron centralizado no host

O cron das instituicoes Moodle e executado por um unico servico `systemd` no
host. Nao use container exclusivo de cron, `crontab` por tenant nem a antiga
lista `config/moodle-cron-tenants.txt`.

O guia completo de arquitetura, instalacao, validacao, operacao e rollback esta
em [cron-moodle-systemd.md](cron-moodle-systemd.md).

Resumo:

1. aplique o label `com.w3soft.moodle.role=tenant` em todos os containers de
   instituicao;
2. recrie os containers para materializar o label;
3. remova containers `_cron` e agendamentos antigos;
4. instale `scripts/moodle-cron-scheduler.sh` em `/usr/local/sbin`;
5. instale a configuracao em `/etc/default`;
6. instale e habilite `systemd/moodle-cron-scheduler.service`;
7. valide descoberta, balanceamento e logs no journal.
