# aws-secur# AWS Secure Cloud Infrastructure

Infraestructura segura en AWS construida con Terraform: red con subredes públicas y privadas, aplicación detrás de un balanceador, base de datos aislada, permisos con mínimo privilegio, auditoría y monitoreo, y un pipeline que revisa la seguridad del código en cada push.

Se desplegó, se probó y se destruyó el mismo día (región `us-east-1`) para no gastar crédito. Todo el código está en `terraform/`.

## Arquitectura

```mermaid
flowchart TB
  Internet((Internet)) -->|HTTP 80| ALB
  subgraph VPC[VPC 10.0.0.0/16]
    subgraph Pub[Subredes públicas - 2 AZ]
      ALB[ALB]
      NAT[NAT Gateway]
    end
    subgraph Priv[Subredes privadas - 2 AZ]
      EC2[EC2 con nginx - sin IP pública]
      RDS[(RDS PostgreSQL)]
    end
  end
  ALB -->|80| EC2
  EC2 -->|5432| RDS
  EC2 -->|443 vía NAT| NAT
  NAT --> Internet
```

## Qué incluye

| Capa | Servicios | Archivo |
|---|---|---|
| Red | VPC, 2 subredes públicas y 2 privadas en 2 zonas, Internet Gateway, NAT Gateway, tablas de rutas | `vpc.tf` |
| Seguridad de red | Security Groups encadenados: internet → ALB → EC2 → RDS | `security_groups.tf` |
| Permisos | Rol IAM para el EC2 con un único permiso (SSM), sin claves ni SSH | `iam.tf` |
| Aplicación | ALB, EC2 en subred privada, RDS PostgreSQL en subredes privadas | `alb.tf`, `ec2.tf`, `rds.tf` |
| Auditoría | CloudTrail multi-región con validación de integridad, bucket cifrado y sin acceso público | `cloudtrail.tf` |
| Monitoreo | CloudWatch: 3 alarmas (CPU del EC2, CPU de la base, servidor no saludable en el ALB) con aviso por mail vía SNS | `cloudwatch.tf` |
| Cumplimiento | AWS Config con 3 reglas: SSH cerrado, S3 sin lectura pública, RDS no pública | `config.tf` |
| CI | GitHub Actions: `terraform fmt` y `validate`, Checkov y Trivy | `.github/workflows/security.yml` |

El despliegue creó **54 recursos**.

## Decisiones de seguridad

- **Una sola entrada desde internet:** solo el ALB es público. El EC2 y la base están en subredes privadas y sin IP pública.
- **Security Groups encadenados:** el EC2 solo acepta tráfico del ALB y la base solo acepta tráfico del EC2. La base no tiene reglas de salida.
- **Sin SSH:** el acceso al servidor es por Session Manager (SSM). No hay puerto 22 ni llaves.
- **Sin claves dentro del servidor:** el EC2 usa un rol IAM con credenciales temporales.
- **IMDSv2 obligatorio** en el EC2, para reducir el riesgo de robo de credenciales por SSRF.
- **Cifrado:** disco del EC2, base de datos y buckets de S3.
- **Contraseña de la base fuera del código:** la genera AWS y queda en Secrets Manager. También se activó la autenticación IAM en RDS.
- **Buckets** de CloudTrail y Config con el acceso público bloqueado.
- **Datos privados fuera del repo:** el mail de las alertas va en `terraform.tfvars`, que Git ignora.

## Capturas

| | |
|---|---|
| Aplicación funcionando detrás del ALB | <img width="640" height="213" alt="Captura de pantalla de 2026-11-10 20-42-53" src="https://github.com/user-attachments/assets/7d6c484d-6887-4c35-a31c-33dad3650c29" />
 |
| Mapa de recursos de la VPC | <img width="1629" height="379" alt="Captura de pantalla de 2026-11-10 20-48-06" src="https://github.com/user-attachments/assets/15af2c06-8814-4b66-a816-b7be47c8655f" />
 |
| EC2 sin IP pública |<img width="1307" height="95" alt="Captura de pantalla de 2026-11-10 20-50-03" src="https://github.com/user-attachments/assets/3d835067-f44b-4ebf-99d0-a3d9a7da6be4" />
 |
| Servidor en estado healthy en el ALB | <img width="814" height="254" alt="photo_5159360457264008470_y" src="https://github.com/user-attachments/assets/8d8ab260-1661-4946-bbf8-bb4121b50b60" />
|
| Base de datos sin acceso desde internet | <img width="586" height="61" alt="Captura de pantalla de 2026-11-10 20-58-45" src="https://github.com/user-attachments/assets/ce2c91bc-d1cd-4def-ba05-8b9036e36518" />
 |
| Regla de entrada de la base: solo desde la app |<img width="1381" height="35" alt="Captura de pantalla de 2026-11-10 21-00-44" src="https://github.com/user-attachments/assets/6b914ac6-c917-47d3-9b71-1d6ec29650b1" />
 |
| CloudTrail | <img width="1280" height="369" alt="photo_5159360457264008472_y" src="https://github.com/user-attachments/assets/1e4037e4-cc3b-41d7-b19b-7db023cda4d7" />
 |
| Reglas de AWS Config | <img width="1464" height="51" alt="Captura de pantalla de 2026-11-10 21-05-07" src="https://github.com/user-attachments/assets/e1f4b35d-9656-4af5-9010-ab08be9557d7" />
 |
| Alarmas de CloudWatch | <img width="1519" height="116" alt="Captura de pantalla de 2026-11-10 21-07-02" src="https://github.com/user-attachments/assets/c2cee387-661b-4dc4-af83-40cdac7997fc" />
 |

## Pipeline de seguridad

En cada push y pull request, GitHub Actions corre:

1. `terraform fmt -check` y `terraform validate`.
2. **Checkov**, que analiza la configuración de Terraform.
3. **Trivy**, que busca configuraciones inseguras de severidad alta o crítica.

El pipeline **no despliega nada** y no usa credenciales de AWS. Checkov y Trivy están en modo informativo: muestran los hallazgos pero no cortan la ejecución.

## Riesgos aceptados

Checkov marcó buenas prácticas que no apliqué a propósito, por costo o por simplicidad. En un entorno de producción irían activadas.

| Hallazgo | Por qué lo acepté | En producción |
|---|---|---|
| ALB con HTTP (`CKV_AWS_2`) | HTTPS necesita dominio y certificado | Puerto 443 con ACM |
| Sin protección contra borrado en RDS (`CKV_AWS_293`) | Necesito poder hacer `terraform destroy` | Activada |
| Sin monitoreo detallado en EC2 (`CKV_AWS_126`) | Cobra extra y no aporta para este proyecto | Activado |
| Sin logs de acceso del ALB (`CKV_AWS_91`) | Requiere otro bucket con política propia | Activados |
| CloudTrail sin clave KMS propia ni SNS (`CKV_AWS_35`, `CKV_AWS_252`) | Agrega costo y complejidad. Los registros van cifrados con AES256 y con validación de integridad | KMS propia y notificaciones |
| SNS sin cifrado (`CKV_AWS_26`) | CloudWatch no puede publicar en un topic cifrado con la clave administrada por AWS | Clave propia con política para CloudWatch |
| Una sola AZ para la base y un solo NAT | Ahorro de costo | RDS Multi-AZ y un NAT por zona |
| Un solo servidor EC2 | Simplicidad | Auto Scaling Group (ver mi proyecto de alta disponibilidad) |

## Limitaciones y lo que quedó afuera

- **Security Hub** y **GuardDuty** no se pudieron activar en mi cuenta (`SubscriptionRequiredException`), por eso no están en el proyecto.
- AWS Config detectó un bucket de S3 con lectura pública que **no pertenece a este proyecto** [COMPLETAR: nombre del bucket y por qué es público].
- La base no recibe tráfico real: el proyecto valida la arquitectura y la red, no una aplicación completa.

## Cómo usarlo

Requisitos: Terraform 1.5 o superior, AWS CLI configurado y una cuenta de AWS.

```bash
cd terraform
echo 'alert_email = "tu-mail@ejemplo.com"' > terraform.tfvars
terraform init
terraform plan
terraform apply
```

Al terminar, `terraform output alb_dns_name` muestra la dirección para abrir en el navegador con `http://`.

**Para no pagar de más:**

```bash
terraform destroy
```

El NAT Gateway, el ALB y la base de datos cobran por hora aunque nadie los use.

## Estructura

```
.
├── .github/workflows/security.yml
├── docs/img/
└── terraform/
    ├── main.tf            ├── alb.tf
    ├── variables.tf       ├── ec2.tf
    ├── outputs.tf         ├── rds.tf
    ├── vpc.tf             ├── cloudtrail.tf
    ├── security_groups.tf ├── cloudwatch.tf
    └── iam.tf             └── config.tf
```e-cloud-infrastructure
