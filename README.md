# Gotenberg en Google Cloud Run

Despliega [Gotenberg](https://gotenberg.dev) (HTML a imagen o PDF con Chromium) como un servicio de Cloud Run, pensado para mantenerse dentro del nivel gratuito de Google Cloud. Lo usa un flujo de n8n que envía el HTML de un slide y recibe un JPEG de 1080x1350.

El servicio queda expuesto a internet y se protege con la autenticación básica de Gotenberg. La clave se genera al desplegar y se guarda en Secret Manager.

## Cómo se mantiene el costo bajo

| Medida | Valor | Efecto |
|---|---|---|
| Imagen | `docker.io/gotenberg/gotenberg:8` directo desde Docker Hub | No ocupa almacenamiento en Artifact Registry |
| Instancias mínimas | 0 | Escala a cero: sin solicitudes no hay cobro de cómputo |
| Instancias máximas | 1 | Tope al gasto máximo |
| Concurrencia | 2 | Dos renders a la vez como máximo por instancia |
| Tiempo máximo | 120 s | Corta solicitudes colgadas |
| Recursos | 1 vCPU y 2 GiB | Chromium no entra en 512 MiB |
| Región | `us-east1` | Región con nivel gratuito |
| Facturación | por solicitud | Solo se cobra mientras se procesa un render |
| Secretos | 1 (la clave); el usuario va como variable normal | Un secreto extra en Secret Manager |

El nivel gratuito de Cloud Run es por cuenta de facturación y se comparte con los demás proyectos de esa cuenta. Consulta los valores vigentes en la página de precios de Cloud Run.

Quedan costos posibles que no son cero: unos centavos por el secreto adicional si ya se superó el límite gratuito de Secret Manager, y la salida de datos si se supera 1 GB al mes. Conviene mantener una alerta de presupuesto en la cuenta de facturación.

## Requisitos

- Google Cloud SDK (`gcloud`) con sesión iniciada y un proyecto con facturación vinculada
- APIs activas: Cloud Run y Secret Manager
- PowerShell 5.1 o superior

## Uso

1. Desplegar (crea la clave si no existe y despliega el servicio):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\desplegar.ps1 -Proyecto <id-del-proyecto>
   ```

   La clave se guarda en `%USERPROFILE%\.gotenberg-cloudrun-credenciales.txt`, fuera del repo. El script no la imprime en pantalla.

2. Probar:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\probar.ps1 -Proyecto <id-del-proyecto>
   ```

   Comprueba que sin credenciales responde 401, que con credenciales responde 200, mide el tiempo de tres renders y verifica que una foto inexistente produzca un 409. Esperado: un slide en menos de 30 s tras el arranque en frío.

3. Configurar n8n: en el nodo que renderiza, usar la URL del servicio (`gcloud run services describe gotenberg --region us-east1 --format="value(status.url)"`), autenticación básica con el usuario y la clave del archivo de credenciales, y procesar los slides de a uno.

## Vigilar el costo

- En la consola de Cloud Run, abrir el servicio `gotenberg` y revisar las métricas de tiempo de instancia facturable y memoria.
- Revisar en Facturación que el gasto del servicio siga en cero.
- Si la memoria se acerca a 2 GiB, subirla con `-Memoria`; si el costo aparece, bajar `max-instances` o reducir el uso desde n8n.

## Notas

- Docker Hub puede limitar las descargas anónimas, y Cloud Run descarga la imagen en cada arranque en frío. Si falla, usar un repositorio remoto de Artifact Registry que haga de caché de Docker Hub; ocupa algo de almacenamiento.
- Tras estar inactivo, el primer render incluye el arranque de la instancia y de Chromium, y tarda más.
- Gotenberg no guarda datos: cada solicitud es independiente.
- No subir a Git el archivo de credenciales ni claves. `.gitignore` excluye los nombres habituales.

## Quitar el servicio

```powershell
gcloud run services delete gotenberg --project <id-del-proyecto> --region us-east1
gcloud secrets delete gotenberg-clave --project <id-del-proyecto>
```
