# Evidencias de despliegue

Entregable 5. Capturas de la corrida contra EKS (Learner Lab, us-east-1):

| Archivo | Qué muestra |
|---|---|
| `alb-ingress.png` | El ALB `oncall-training-api` y su DNS (en lugar de API Gateway, ver [api.md](../api.md)) |
| `eks-pods.png` | `make status`: nodos y pods corriendo en `app`, `injector` y `mock` |
| `docker-logs.png` | `kubectl -n app logs deploy/backend-api` y `kubectl -n injector logs deploy/injector` durante la demo |
| `dynamodb-sessions.png` | La tabla `Sessions` con datos de prueba |
| `curl-pruebas.png` | Las pruebas de [api.md](../api.md#pruebas-curl) con su respuesta real |

**URL de la API:** `TODO: http://<alb-dns>/api`
