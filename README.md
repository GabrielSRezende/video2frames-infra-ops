# video2frames-infra-ops

Repositório central de infraestrutura e operação do sistema **Video2Frames** (Pós-Tech Fase 05): observabilidade compartilhada, emulação de AWS para desenvolvimento local, e o compose que sobe o pipeline inteiro de uma vez para teste ponta a ponta.

No futuro este repositório também vai concentrar o **Terraform** que provisiona a infraestrutura real na AWS; cada serviço (`video2frames-auth-service`, `video2frames-video-service`, `video2frames-processing-service`, `video2frames-notification-service`) terá seu próprio GitHub Actions de build/deploy/destroy para Kubernetes. Por enquanto, o escopo aqui é só: observabilidade + LocalStack + compose de teste local.

📄 **[Documentação de arquitetura do sistema](docs/arquitetura.md)**: visão geral, a saga coreografada entre os serviços (passos e compensações), estratégia de escalabilidade horizontal e as principais decisões de projeto.

## Pré-requisito

Os 4 repositórios de serviço e o front precisam estar clonados como **pastas irmãs** desta, isto é:

```
C:\Projetos\
├── video2frames-infra-ops\        (este repositório)
├── video2frames-auth-service\
├── video2frames-video-service\
├── video2frames-processing-service\
├── video2frames-notification-service\
└── video2frames-web\
```

`docker-compose.full.yml` referencia os outros repositórios via `build: ../video2frames-<nome>-service`.

## Estrutura

```
video2frames-infra-ops/
├── docker-compose.yml         # infraestrutura: LocalStack + Prometheus + Grafana + rede compartilhada
├── docker-compose.full.yml    # overlay: os 4 serviços + seus bancos (usar junto com o arquivo acima)
├── localstack/init/           # script que cria bucket S3 + filas SQS no LocalStack
├── prometheus/prometheus.yml  # scrape config dos 4 serviços
└── grafana/                   # datasource + dashboard provisionados automaticamente
```

## Modo 1: só infraestrutura (para desenvolver um serviço por vez)

Se você está trabalhando em **um único serviço** (rodando ele via `docker compose up -d` no próprio repositório dele, ou via `./mvnw spring-boot:run`), só precisa da infraestrutura compartilhada de pé:

```bash
docker compose up -d
```

Isso sobe:
- **LocalStack** (`video2frames-localstack`, porta `4566`). Cria a rede Docker `video2frames-net` (usada pelos `docker-compose.yml` de `video2frames-video-service`, `video2frames-processing-service` e `video2frames-notification-service` para se conectar a este LocalStack) e provisiona o bucket S3 `video2frames` mais as 5 filas SQS.
- **Prometheus** (porta `9090`). Faz *scrape* de `/actuator/prometheus` dos 4 serviços via `host.docker.internal`, e por isso funciona independente de como cada serviço está rodando (container ou host), desde que a porta esteja publicada.
- **Grafana** (porta `3000`, login `admin`/`admin`), com o dashboard **"Video2Frames - Overview"** já provisionado.

> Suba este compose **antes** de subir o `docker-compose.yml` de `video2frames-video-service`/`video2frames-processing-service`/`video2frames-notification-service`, já que eles esperam a rede `video2frames-net` existindo.

## Modo 2: pipeline completo (testar tudo de uma vez)

Para subir os 4 serviços + front + bancos + LocalStack + Prometheus + Grafana com um único comando (builda as imagens Docker de cada serviço/do front a partir do código-fonte irmão):

```bash
docker compose -f docker-compose.yml -f docker-compose.full.yml up -d --build
```

Isso sobe, além da infraestrutura do Modo 1:

| Serviço | Porta | Depende de |
|---|---|---|
| `authdb` (Postgres) | 5432 | — |
| `videodb` (Postgres) | 5433 | — |
| `auth-service` | 8081 | `authdb` |
| `video-service` | 8082 | `videodb`, `localstack` |
| `processing-service` | 8083 | `localstack` |
| `notification-service` | 8084 | `localstack` |
| `web` (Angular, servido via nginx) | 4200 | `auth-service`, `video-service` |

O `web` é buildado com `ng build --configuration development`, que embute `http://localhost:8081/api` e `http://localhost:8082/api` como URLs de API. São exatamente as portas publicadas pelos containers acima, então tudo funciona sem configuração extra. O CORS do `auth-service`/`video-service` já libera `http://localhost:4200` por padrão.

Depois de subir (dê ~10-20s para os apps iniciarem; o build do `web` pode levar mais tempo na primeira vez por causa do `npm ci`):
- Front: `http://localhost:4200`
- Health checks: `http://localhost:808{1,2,3,4}/actuator/health`
- Prometheus targets: `http://localhost:9090/targets` (os 4 backends devem aparecer `UP`)
- Grafana: `http://localhost:3000`

> Não rode o Modo 2 ao mesmo tempo que o `docker-compose.yml` individual de um serviço, porque ambos tentam publicar as mesmas portas de host (ex: `8082`, `5433`).

### Credenciais de e-mail

O `notification-service` envia o e-mail de falha por SMTP e não traz credenciais no código. Para o envio funcionar, copie `.env.example` para `.env` nesta pasta e preencha:

```
SMTP_USERNAME=seu-email@gmail.com
SMTP_PASSWORD=senha-de-app-do-gmail
```

O `.env` está no `.gitignore` e não deve ser commitado. No Gmail, use uma senha de app (Conta Google > Segurança > Senhas de app), não a senha da conta. Sem essas variáveis o sistema sobe normalmente, mas o envio do e-mail falha.

## Derrubando tudo

```bash
docker compose -f docker-compose.yml -f docker-compose.full.yml down
```

(ou só `docker compose down` se você só tiver subido o Modo 1).

## Migração futura para AWS

- **LocalStack** → serviços reais (S3, SQS) provisionados via Terraform, com filas/roles/políticas versionadas neste mesmo repositório.
- **Prometheus/Grafana locais** → Amazon Managed Service for Prometheus (AMP) + Amazon Managed Grafana, mantendo os mesmos endpoints `/actuator/prometheus` como fonte; scrape config passa a usar *service discovery* (ECS Service Discovery/Cloud Map ou `kubernetes_sd_configs` no EKS) em vez de alvos fixos.
- **`docker-compose.full.yml`** → substituído pelos manifests/Helm charts de Kubernetes de cada serviço, publicados via GitHub Actions (build da imagem + deploy/destroy no cluster).
