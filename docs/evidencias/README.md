# Evidencias de despliegue

Entregable 5. Capturas de una corrida completa del caso de uso contra EKS (Learner Lab, us-east-1), el 2026-11-05/06. La API entra por un ALB en lugar de API Gateway ([api.md](../api.md#por-qué-alb-y-no-api-gateway)) y el backend corre como contenedor en EKS en lugar de una EC2 suelta.

| Qué muestra | Cómo se obtiene | Evidencia |
|---|---|---|
| El ALB `oncall-training-api`: activo, de tipo application, internet-facing, en la VPC del cluster | Consola EC2 → Load Balancers | [alb-ingress.png](alb-ingress.png) |
| Los 2 nodos `Ready`, los pods corriendo en `app` (api ×2, worker), `injector` y `mock` (gateway, orders ×2, worker-svc), los tags de las imágenes y el DNS del ALB | `make status` | [eks-pods.png](eks-pods.png) |
| Logs del contenedor de la API: arranque en modo `dev` / `direct` y los requests que llegan por el ALB (`POST /api/sessions` → 201) | `kubectl -n app logs deploy/backend-api` | [docker-logs-backend-api.png](docker-logs-backend-api.png) |
| Logs del injector: recibe la falla de SQS, escala `orders` a cero, marca la sesión `INCIDENT_ACTIVE` y borra el mensaje | `kubectl -n injector logs deploy/injector` | [docker-logs-injector.png](docker-logs-injector.png) |
| Logs del gateway del sistema simulado: errores `ECONNREFUSED` y timeouts hacia `orders` durante el incidente | `kubectl -n mock logs deploy/gateway` | [docker-logs-gateway.png](docker-logs-gateway.png) |
| La tabla `Sessions` en DynamoDB con sesiones de prueba (PK `user_id`, SK `session_id`) | Consola DynamoDB → Explore items | [dynamodb-sessions.png](dynamodb-sessions.png) |
| Los tres repositorios en ECR (backend, injector, mock-system) con tags inmutables y cifrado AES-256 | Consola ECR | [ecr-imagenes.png](ecr-imagenes.png) |
| Las pruebas de [api.md](../api.md#pruebas-curl) contra el ALB: el caso de uso completo (201 → `INCIDENT_ACTIVE` → 202 → `RESOLVED`, score 982) y cada error (400, 401, 404, 409); la respuesta de `/logs` está recortada | `curl` contra `http://<alb-dns>/api` | [curl-pruebas.txt](curl-pruebas.txt) |

**URL de la API:** `http://oncall-training-api-1197004083.us-east-1.elb.amazonaws.com/api` en esta corrida. El DNS cambia en cada `make cluster-up`; se muestra en vivo con `make status`.

Las respuestas completas de cada endpoint, incluidos los errores, están en [api.md § Respuestas reales](../api.md#respuestas-reales).
