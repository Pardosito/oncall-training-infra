# Pendientes para la entrega final

Entregable 6. Equipo Cafeinomanos: **Ian** Rodríguez (infra, orquestación) y **Juan Pablo** González (backend, frontend). Lo que ya funciona está en verde en el [diagrama](solucion.png); esta lista es lo que falta para la entrega final.

| # | Pendiente | Quién | Para |
|---|---|---|---|
| 1 | Step Functions (`oncall-training-scenario`) orquesta la sesión en lugar del modo directo actual (el backend manda la falla a SQS); el worker hace `SendTaskSuccess` | Ian (máquina de estados), Juan Pablo (worker) | Nov 19 |
| 2 | ElastiCache (Valkey): lock global de sesión y snapshots del dashboard; quitar el `Scan` temporal de sesión activa | Ian (cluster), Juan Pablo (cliente Redis) | Nov 19 |
| 3 | Cognito: login real en la SPA y verificación del token en el backend; quitar `AUTH_MODE=dev` | Juan Pablo (backend + frontend), Ian (user pool) | Nov 19 |
| 4 | Sitio en S3 + CloudFront: `/` → bucket `site`, `/api/*` → ALB, HTTPS; el ALB solo acepta tráfico de CloudFront | Ian (CloudFront), Juan Pablo (deploy de la SPA) | Nov 19 |
| 5 | NetworkPolicies default-deny entre `app`, `injector` y `mock` | Ian | Nov 19 |
| 6 | Logs de eventos a S3 + Glue/Athena para las gráficas de desempeño y el historial (`/api/me/*`, ranking) | Juan Pablo (consultas, rutas), Ian (Glue, workgroup) | Nov 26 |
| 7 | Prueba e2e del camino feliz contra el stack desplegado | Ambos | Nov 26 |
| 8 | Documentación final: diagrama actualizado, decisiones por escrito, README final | Ambos | Nov 26 |

## Riesgo principal y plan B

| Riesgo | Plan B |
|---|---|
| Step Functions o el LB controller fallan con LabRole al cambiar de cuenta | Mantener el modo directo actual (el backend manda la falla a SQS), que ya funciona |
| El presupuesto del lab se acaba con el cluster encendido (≈ $6/día) | `make cluster-down` al final de cada sesión; la demo de respaldo corre la SPA con `pnpm dev:mocks` y el backend con `pnpm dev:memory` |
| Reiniciar el lab tarda | `make creds` → `make cluster-up` (~20 min) → `make deploy`; foundation (datos, imágenes) no se borra |
