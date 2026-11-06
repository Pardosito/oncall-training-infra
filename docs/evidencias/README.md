# Evidencias de despliegue

Entregable 5. Capturas de una corrida completa del caso de uso contra EKS (Learner Lab, us-east-1). La API entra por un ALB en lugar de API Gateway ([api.md](../api.md#por-qué-alb-y-no-api-gateway)) y el backend corre como contenedor en EKS en lugar de una EC2 suelta.

| Archivo | Qué muestra | Cómo se obtiene |
|---|---|---|
| `alb-ingress.png` | El ALB `oncall-training-api`, su DNS y el target group con los pods `healthy` | Consola EC2 → Load Balancers |
| `eks-pods.png` | Nodos y pods corriendo en `app`, `injector` y `mock` | `make status` |
| `docker-logs.png` | Logs de los contenedores durante la demo: la API, el injector aplicando la falla y el gateway con errores | `kubectl -n app logs deploy/backend-api` · `kubectl -n injector logs deploy/injector` · `kubectl -n mock logs deploy/gateway` |
| `dynamodb-sessions.png` | La tabla `Sessions` con la sesión `RESOLVED` y su puntaje | Consola DynamoDB → Explore items |
| `ecr-imagenes.png` | Las tres imágenes en ECR, etiquetadas con el git SHA | Consola ECR |
| `curl-pruebas.png` | Las pruebas de [api.md](../api.md#pruebas-curl) contra el ALB con su respuesta | Terminal |

**URL de la API:** `http://<alb-dns>/api`. El DNS cambia en cada `make cluster-up`; se muestra en vivo con `make status`.

Las respuestas completas de cada endpoint, incluidos los errores, están en [api.md § Respuestas reales](../api.md#respuestas-reales).
