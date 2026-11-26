# Pendientes para la entrega final

Entregable 6. Equipo Cafeinomanos: **Ian** Rodríguez (infra, orquestación) y **Juan Pablo** González (backend, frontend). Lo que ya funciona está en verde en el [diagrama](solucion.png); esta lista es lo que falta para la entrega final.

Estado al 2026-11-26:

| # | Pendiente | Quién | Para | Estado |
|---|---|---|---|---|
| 1 | Step Functions (`oncall-training-scenario`) orquesta la sesión en lugar del modo directo; el worker hace `SendTaskSuccess` | Ian (máquina de estados), Juan Pablo (worker) | Nov 19 | ✅ Hecho (D-36): probado en EKS con resolve, abandon y timeout |
| 2 | ElastiCache (Valkey): lock global de sesión y snapshots del dashboard; quitar el `Scan` temporal de sesión activa | Ian (cluster), Juan Pablo (cliente Redis) | Nov 19 | ✅ Hecho |
| 3 | Cognito: login real en la SPA y verificación del token en el backend; quitar `AUTH_MODE=dev` | Juan Pablo (backend + frontend), Ian (user pool) | Nov 19 | ✅ Hecho, con login estilo Carbon y registro con código por email (D-34, D-35) |
| 4 | Sitio en S3 + CloudFront: `/` → bucket `site`, `/api/*` → ALB, HTTPS | Ian (CloudFront), Juan Pablo (deploy de la SPA) | Nov 19 | 🔁 Cambiado: **sin CloudFront** porque el Learner Lab no lo permite; la SPA está en el website endpoint de S3 (D-31) y la API tiene HTTPS con **API Gateway** delante de un ALB interno (D-33) |
| 5 | NetworkPolicies default-deny entre `app`, `injector` y `mock` | Ian | Nov 19 | ✅ Hecho: aplicadas en EKS y probadas (el injector no alcanza los pods; probes, ALB e incidente completo funcionan) |
| 6 | Logs de eventos a S3 + Glue/Athena para las gráficas de desempeño y el historial | Juan Pablo (consultas, rutas), Ian (Glue, workgroup) | Nov 26 | 🔁 Cambiado: **sin Glue ni Athena** porque el rol del Learner Lab no puede usarlos; historial, gráficas y ranking salen de DynamoDB (D-37). Los logs por sesión sí se guardan en S3 |
| 7 | Prueba e2e del camino feliz contra el stack desplegado | Ambos | Nov 26 | ✅ Hecho manualmente (login, escenario resuelto, historial y ranking) |
| 8 | Documentación final: diagrama actualizado, decisiones por escrito, README final | Ambos | Nov 26 | ✅ Diagrama y decisiones al día; README final pendiente |

## Riesgo principal y plan B

| Riesgo | Plan B |
|---|---|
| Step Functions o el LB controller fallan con LabRole al cambiar de cuenta | Volver al modo directo (`ORCHESTRATION_MODE=direct make render-config` y `make deploy`), que sigue funcionando |
| El presupuesto del lab se acaba con el cluster encendido (≈ $6/día) | `make cluster-down` al final de cada sesión; la demo de respaldo corre la SPA con `pnpm dev:mocks` y el backend con `pnpm dev:memory` |
| Reiniciar el lab tarda | `make creds` → `make cluster-up` (~20 min) → `make deploy`; foundation (datos, imágenes) no se borra |
