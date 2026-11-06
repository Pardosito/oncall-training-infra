# Diseño de la API

Entregable 3 de la entrega intermedia. El contrato completo es el [`openapi.json` del backend](https://github.com/Pardosito/oncall-training-backend/blob/main/openapi/openapi.json) (se sirve también en `GET /api/openapi.json`).

> [!IMPORTANT]
> **Nuestra entrada no es API Gateway.** El backend corre en **EKS** (no en una EC2 suelta) y la API se expone con un **Application Load Balancer** que crea el AWS Load Balancer Controller desde un `Ingress` de Kubernetes. El ALB cumple el papel de API Gateway en la guía: recibe el request, lo pasa tal cual (equivalente a *HTTP proxy*) a los pods del backend y regresa la respuesta. Ver [DECISIONS](DECISIONS.md) y la sección [¿Por qué ALB y no API Gateway?](#por-qué-alb-y-no-api-gateway).

## Flujo de un request

```mermaid
flowchart LR
    C["Cliente<br/>SPA (Vite) o Postman / curl"] -- HTTP :80 --> ALB["ALB oncall-training-api<br/>Ingress /api/*<br/>solo IPs de la demo"]
    ALB -- "proxy (IP target)" --> API["EKS · ns app<br/>backend-api ×2<br/>contenedor :3000"]
    API -- AWS SDK --> DDB[(DynamoDB<br/>Sessions)]
    API -- SendMessage --> FQ[[SQS faults]]
    API -- SendMessage --> UQ[[SQS user-actions.fifo]]
    API -- GetObject --> S3[(S3 files<br/>scenarios/)]
    FQ --> INJ["injector"] --> MOCK["ns mock<br/>gateway → orders → worker-svc"]
    UQ --> W["backend-worker"] --> MOCK
```

La respuesta regresa por el mismo camino hasta el cliente. Las acciones del usuario son asíncronas: la API responde **202** y el worker las aplica en orden (FIFO por sesión).

## Stage y URL de invocación

| | Valor |
|---|---|
| Entorno | `lab` (un solo entorno; equivale al stage `dev` de la guía) |
| URL base | `http://<alb-dns>/api` donde `<alb-dns>` = `oncall-training-api-<id>.us-east-1.elb.amazonaws.com` |
| Cómo obtenerla | `make status` o `kubectl -n app get ingress backend-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` |
| URL de la demo | `TODO: pegar el DNS del ALB el día de la revisión (cambia en cada make cluster-up)` |

> [!NOTE]
> El DNS del ALB cambia cada vez que se recrea el cluster (Learner Lab). Por eso no está fijo en el código: la SPA lo recibe en `API_PROXY_TARGET` y los scripts lo buscan por el nombre fijo del balanceador.

## Recursos

El `Ingress` publica solo dos rutas: el prefijo `/api` y `/healthz` (el health check del ALB). `/readyz` queda interno, para la readiness probe de Kubernetes.

**Integración:** proxy. El ALB reenvía método, ruta, headers, query string y cuerpo sin transformar; toda la validación (zod) vive en el backend, que es la única fuente del contrato (`openapi.json`). No hay mapping templates.

**Autenticación en el MVP:** `AUTH_MODE=dev`, cada request manda `x-dev-user: <id>[:<nombre>]`. Cognito con `Authorization: Bearer <token>` es **planeado** para la final.

| Recurso | Método | Integración | Destino | Request | Response esperada | Estado |
|---|---|---|---|---|---|---|
| `/healthz` | GET | proxy | `backend-api` GET `/healthz` | — | 200 `{status:"ok"}` | desplegado |
| `/api/scenarios` | GET | proxy | `backend-api` GET `/api/scenarios` | — | 200 lista de `ScenarioSummary` | desplegado |
| `/api/scenarios/{scenarioId}` | GET | proxy | `backend-api` GET `/api/scenarios/{scenarioId}` | id en la ruta | 200 `ScenarioPublic`; 404 si no existe | desplegado |
| `/api/sessions` | POST | proxy | `backend-api` POST `/api/sessions` | `{ "scenarioId": "orders-down" }` | 201 `{ sessionId }`; 400 cuerpo inválido; 404 escenario; 409 `SESSION_BUSY` | desplegado |
| `/api/sessions/{sessionId}` | GET | proxy | `backend-api` GET `/api/sessions/{sessionId}` | id en la ruta | 200 `SessionView`; 404 si no existe o es de otro usuario | desplegado |
| `/api/sessions/{sessionId}/dashboard` | GET | proxy | `backend-api` GET `…/dashboard` | id en la ruta | 200 `DashboardSnapshot` (réplicas, salud, eventos, acciones disponibles) | desplegado |
| `/api/sessions/{sessionId}/actions` | POST | proxy | `backend-api` POST `…/actions` → SQS `user-actions.fifo` | `{ type, target?, params? }` | 202 `{ actionId }`; 400; 409 `SESSION_NOT_ACTIVE`; 422 `ACTION_NOT_ALLOWED` | desplegado |
| `/api/sessions/{sessionId}/logs?service=` | GET | proxy | `backend-api` GET `…/logs` → logs del pod en ns `mock` | `service` en el query | 200 `{ service, lines[] }`; 409; 422 | desplegado |
| `/api/sessions/{sessionId}/abandon` | POST | proxy | `backend-api` POST `…/abandon` | — | 202; 404; 409 | desplegado |
| `/api/me/sessions` | GET | proxy | `backend-api` | `limit`, `cursor` | 200 `{ items, nextCursor? }` | planeado |
| `/api/me/stats/{queryName}` | GET | proxy | `backend-api` → Athena | `score-over-time` \| `ttd-ttr-by-attempt` | 200 `{ rows }`; 504 timeout de Athena | planeado |
| `/api/leaderboard/{scenarioId}` | GET | proxy | `backend-api` → GSI `Leaderboard` | id en la ruta | 200 top 10 | planeado |

### Requests mal formados

Todos los errores tienen el mismo cuerpo, con un `requestId` que también llega en el header `x-request-id`:

```json
{ "error": { "code": "VALIDATION_ERROR", "message": "…", "details": { "issues": [] }, "requestId": "01J…" } }
```

| Caso | Respuesta | Dónde se valida |
|---|---|---|
| JSON inválido | 400 `MALFORMED_JSON` | backend, middleware de Express |
| Falta un campo o tiene otro tipo | 400 `VALIDATION_ERROR` | backend, esquema zod de la ruta |
| Cuerpo > 100 kB / sin `Content-Type: application/json` | 413 / 415 | backend |
| Sin `x-dev-user` (o token) | 401 `UNAUTHORIZED` | backend, middleware de auth |
| Ruta que no existe | 404 `NOT_FOUND` | backend |

## Pruebas (curl)

```bash
API=http://<alb-dns>/api
U='x-dev-user: demo:demo'

# GET: escenarios disponibles
curl -s "$API/scenarios" -H "$U"

# POST: iniciar una sesión (manda la falla con delay de warmupSeconds)
curl -s -X POST "$API/sessions" -H "$U" -H 'Content-Type: application/json' \
  -d '{"scenarioId":"orders-down"}'
# → {"sessionId":"01J…"}
SID=<sessionId>

# GET: estado y dashboard (la SPA lo consulta cada 2 s)
curl -s "$API/sessions/$SID" -H "$U"
curl -s "$API/sessions/$SID/dashboard" -H "$U"

# POST: acciones del usuario
curl -s -X POST "$API/sessions/$SID/actions" -H "$U" -H 'Content-Type: application/json' -d '{"type":"ACKNOWLEDGE"}'
curl -s "$API/sessions/$SID/logs?service=gateway" -H "$U"
curl -s -X POST "$API/sessions/$SID/actions" -H "$U" -H 'Content-Type: application/json' \
  -d '{"type":"SCALE_DEPLOYMENT","target":"orders","params":{"replicas":2}}'

# Error: cuerpo inválido → 400 VALIDATION_ERROR
curl -s -X POST "$API/sessions" -H "$U" -H 'Content-Type: application/json' -d '{}'
```

**Respuestas reales:** `TODO: pegar la salida de cada comando (o capturas en docs/evidencias/) en la corrida contra EKS.`

## ¿Por qué ALB y no API Gateway?

| | ALB + Ingress (elegido) | API Gateway |
|---|---|---|
| Cómo llega a los pods | Directo a las IPs de los pods (`target-type: ip`); el controller actualiza los targets cuando Kubernetes reprograma pods | Necesita un ALB o NLB interno igual, más un VPC Link |
| Infraestructura como código | Lo declara el `Ingress` en `k8s/overlays/aws`, junto con el resto de los manifiestos | Recursos aparte en Terraform que hay que mantener en sincronía con el cluster |
| Validación y contrato | En el backend con zod, fuente única en `openapi.json` | Se duplicaría en modelos de API Gateway |
| Costo | ≈ $0.025/h, solo mientras el cluster está arriba | Por request, más el balanceador que de todos modos hace falta |
| Desventaja | Sin throttling, API keys ni stages integrados; HTTP en el MVP | — |

En la final, CloudFront se pone delante (`/api/*` → ALB) para tener HTTPS y una sola URL con el sitio (ver [pendientes](pendientes.md)).
