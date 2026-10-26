# Modelos disponibles en la API (Aliyun MaaS)

Endpoint configurado en este entorno:

- `ANTHROPIC_BASE_URL = https://llm-kcqiiw0if0n8a3fc.ap-southeast-1.maas.aliyuncs.com/apps/anthropic`
- Autenticación: la misma `ANTHROPIC_API_KEY` del entorno.
- Verificado el 2026-10-25: DeepSeek, GLM y Kimi responden tanto por la ruta
  Anthropic (`/v1/messages`) como por la compatible con OpenAI (`/compatible-mode/v1`).

## IDs exactos de los modelos

### DeepSeek
| ID | Notas |
|---|---|
| `deepseek-v4-pro` | El más capaz |
| `deepseek-v4-pro-0813` | Snapshot fechado |
| `deepseek-v4-flash-0731` | Rápido/económico |
| `deepseek-v4.1-flash` | Rápido/económico |
| `deepseek-v4.1-flash-1017` | Snapshot fechado |

### GLM (Zhipu)
| ID | Notas |
|---|---|
| `glm-5.3` | Recomendado |
| `glm-5.3-prime` | Variante prime |
| `ZHIPU/GLM-5.3` | Alias con prefijo de vendor |
| `glm-5.2` | |
| `glm-5.2-fast-preview` | |
| `glm-5.1` | |

### Kimi (Moonshot)
| ID | Notas |
|---|---|
| `kimi-k3` | Recomendado |
| `kimi/kimi-k3` | Alias con prefijo de vendor |
| `kimi-k2.7-code` | Especializado en código |

> Los tres familias son **modelos de razonamiento**: generan un bloque
> `thinking` antes de la respuesta final. Dales `max_tokens` generoso.

### Qwen (texto / chat — usables con `/model` en el CLI)
| Serie | IDs |
|---|---|
| Qwen3.8 (actual) | `qwen3.8-max`, `qwen3.8-max-0902`, `qwen3.8-flash`, `qwen3.8-27b`, `qwen3.8-2.4t-a95b` |
| Qwen3.7 | `qwen3.7-max`, `qwen3.7-max-preview`, `qwen3.7-max-2026-05-17`, `qwen3.7-max-2026-05-20`, `qwen3.7-max-2026-06-08`, `qwen3.7-plus`, `qwen3.7-plus-2026-05-26`, `qwen3.7-flash`, `qwen3.7-flash-2026-07-15` |
| Qwen3.6 | `qwen3.6-plus`, `qwen3.6-plus-2026-04-02`, `qwen3.6-flash`, `qwen3.6-flash-2026-04-16`, `qwen3.6-27b`, `qwen3.6-35b-a3b` |
| Qwen3.5 | `qwen3.5-plus`, `qwen3.5-plus-2026-02-15`, `qwen3.5-plus-2026-04-20`, `qwen3.5-flash`, `qwen3.5-flash-2026-02-23`, `qwen3.5-397b-a17b`, `qwen3.5-122b-a10b`, `qwen3.5-35b-a3b`, `qwen3.5-27b` |
| Clásicos | `qwen-max`, `qwen-plus`, `qwen-plus-latest`, `qwen-plus-2025-01-25`, `qwen-plus-2025-04-28`, `qwen-plus-2025-07-14`, `qwen-plus-2025-12-01`, `qwen-flash`, `qwen2-7b-instruct`, `qwq-plus-2025-03-05` |
| Personaje | `qwen-plus-character`, `qwen-flash-character` |
| Código | `qwen3-coder-flash` |

### Qwen (multimodales y otros)
- Visión: `qwen3-vl-plus`, `qwen-vl-ocr-2025-11-20`
- Omni: `qwen3-omni-flash`, `qwen3.5-omni-flash` (+ `-realtime`, snapshots), `qwen3.5-omni-plus` (+ `-realtime`, snapshots), `qwen3.8-omni-flash` (+ `-realtime`)
- Audio/ASR/TTS: `qwen-audio-3.0-asr-flash`, `qwen-audio-3.1-realtime-plus`, `qwen3-asr-flash-realtime`, `qwen3-tts-flash` (+ `-realtime`), `qwen3-s2s-flash-realtime`
- Traducción: `qwen-mt-plus`, `qwen-mt-flash`, `qwen-mt-lite`, `qwen3-livetranslate-flash` (+ snapshot), `qwen3.5-livetranslate-flash-realtime` (+ snapshot), `qwen3.8-livetranslate-flash-realtime`
- Imagen: `qwen-image-3.0`, `qwen-image-3.0-pro`, `qwen-image-2.0`, `qwen-image-2.0-pro` (+ snapshots)
- Embeddings: `qwen3.7-text-embedding`, `text-embedding-v3`, `text-embedding-v4`

### Mapeo actual del Claude Code CLI
| Alias / rol | Modelo |
|---|---|
| Principal (`ANTHROPIC_MODEL`, alias `opus`) | `qwen3.8-max` |
| Alias `sonnet` / subagentes (`CLAUDE_CODE_SUBAGENT_MODEL`) | `qwen3.7-plus` |
| Alias `haiku` | `qwen3.8-flash` |

## Niveles de razonamiento por modelo

El razonamiento se controla con `effortLevel` del CLI (`low` / `medium` / `high`,
configurable en `/config` o con `CLAUDE_EFFORT=<nivel>`), que se traduce a
`thinking.budget_tokens` en la petición. Verificado empíricamente el 2026-10-25
(mismo prompt con budget 100 vs 2000):

| Modelo | Razonamiento | ¿Respeta el budget/niveles? | Evidencia (chars de thinking, budget 100 → 2000) |
|---|---|---|---|
| `qwen3.8-max` | ✅ thinking + texto | ✅ Sí, escala con el nivel | 298 → 785 (2.6×) |
| `qwen3.7-plus` | ✅ thinking + texto | ✅ Sí (familia Qwen) | — |
| `qwen3.8-flash` | ✅ thinking + texto | ✅ Sí (familia Qwen) | — |
| `qwen3.5-plus` | ✅ thinking + texto | ✅ Sí (familia Qwen) | — |
| `deepseek-v4-pro` | ✅ thinking + texto | ✅ Sí, escala con el nivel | 376 → 1,378 (3.7×) |
| `glm-5.3` | ✅ thinking + texto | ⚠️ No — ignora el budget, razona a fondo siempre | 5,458 → 3,948 (sin correlación) |
| `kimi-k3` | ✅ razona siempre | ❌ Rechaza `thinking_budget` (`InvalidParameter`); no admite control | — |
| `qwen3-coder-flash` | ❌ No razona (solo texto) | n/a — respuestas directas, sin latencia de thinking | — |

Implicaciones prácticas:
- **Qwen y DeepSeek**: `low` ahorra output y latencia de verdad; `high` da razonamiento profundo.
- **GLM**: `effortLevel: low` no ahorra casi nada — siempre piensa completo.
- **Kimi**: cada llamada paga su thinking completo (y es el modelo más caro).
- **qwen3-coder-flash**: útil para autocompletar/refactors simples sin esperar razonamiento.
- Nota: con `kimi-k3` no enviar el parámetro `thinking`; si se envía con `budget_tokens`, la API responde error.

## Precios (USD por 1M tokens — Alibaba Cloud Model Studio, verificado 2026-10-25)

| Modelo | Input | Output | Notas |
|---|---|---|---|
| `qwen3.8-max` | $2.00 | $6.00 | tarifa única |
| `qwen3.7-max` | $2.50 | $7.50 | |
| `qwen3.7-plus` | $0.40 / $1.20 | $1.60 / $4.80 | ≤256K / 256K–1M; −20 % promo |
| `qwen3.8-flash` | $0.15 | $0.47 | el más barato con razonamiento |
| `qwen3.5-plus` | $0.40 / $0.50 | $2.40 / $3.00 | ≤256K / 256K–1M |
| `qwen3-coder-flash` | $0.30–$1.60 | $1.50–$9.60 | tiers por contexto (≤32K / ≤128K / ≤256K / ≤1M) |
| `glm-5.3` | $1.40 | $4.40 | flat-rate |
| `glm-5.2` | $1.40 | $4.40 | flat-rate |
| `deepseek-v4-pro` | $2.40 | $4.80 | tarifa única |
| `deepseek-v4.1-flash` | $0.30 / $0.15 | $1.20 / $0.60 | hora pico (08:00–22:00 UTC+8) / valle |
| `kimi-k3` | $3.00 | $15.00 | ⚠️ el más caro; razona siempre |
| `kimi-k2.7-code` | $0.95 | $4.00 | |

**Sin precio publicado** (están en el endpoint pero no en la página de facturación):
`glm-5.3-prime`, `glm-5.1`, `glm-5.2-fast-preview`, `deepseek-v4-flash-0731`,
`qwen3.7-flash`, series `qwen3.6-*`, `qwen3.5-flash`, `qwen-max/plus/flash` clásicos.

**Descuentos generales**: cache hits ≈ 10 % del input; llamadas batch a mitad de
precio; free quota de 1M tokens (90 días, región Singapur) en modelos seleccionados.

**Costo/valor rápido**:
- Baratos con razonamiento: `qwen3.8-flash`, `qwen3.7-plus`
- Terceros rentables: `glm-5.3`, `deepseek-v4.1-flash` (hora valle)
- Premium: `kimi-k3` — solo para tareas donde justifique el precio

## Privacidad y datos

Política oficial de Alibaba Cloud Model Studio (verificada 2026-10-25):

- **No entrenan con tu uso de API.** El aviso de privacidad establece:
  *"Alibaba Cloud strictly protects your data privacy and will never use your
  data for model training."* Es la política por defecto de la API comercial —
  no hay opt-out que configurar porque no hay entrenamiento que desactivar.
- La divulgación de datos de Qwen/Wan refuerza: Model Studio **no usa datos de
  negocio de clientes para desarrollar o mejorar modelos sin consentimiento
  explícito**.
- **Sí almacenan** inputs/outputs de las llamadas (logs operativos, facturación,
  seguridad); no publican el plazo de retención.
- **Matiz importante**: el producto consumer (chat.qwen.ai / app gratuita) sí
  puede usar contenido desidentificado para mejorar modelos. La garantía de
  no-entrenamiento aplica a la **API**, que es lo que usa este CLI.
- **Modelos de terceros** (`deepseek-*`, `glm-*`, `kimi-*`): se sirven vía la
  infraestructura de Alibaba y aplican sus términos; la cadena de confianza pasa
  por Alibaba, no hay contrato directo con DeepSeek/Zhipu/Moonshot. Para código
  muy sensible, los Qwen tienen la política más directa y verificable.
- Para garantías contractuales más fuertes (retención, jurisdicción,
  subprocessors): revisar el DPA/acuerdo enterprise de la cuenta Alibaba Cloud.

Higiene recomendada (la política no evita fugas accidentales):
- No pegar claves, tokens ni credenciales en los prompts.
- Mantener repos ultra-sensibles fuera del working directory del CLI cuando se
  usen modelos de terceros.
- Para lo más crítico (p. ej. algoritmos de control o reward shaping de RL):
  considerar ejecución local (CUDA 12.9 disponible; Qwen3-Coder corre bien con
  Ollama/vLLM sin salir de la máquina).

Fuentes:
- Privacy notice: https://www.alibabacloud.com/help/en/model-studio/privacy-notice
- FAQ (Is my data secure?): https://www.alibabacloud.com/help/en/model-studio/faq-about-alibaba-cloud-model-studio
- Training data disclosure: https://www.alibabacloud.com/help/en/model-studio/qwen-and-wan-training-data-disclosure
- Privacy Policy internacional: https://www.alibabacloud.com/help/en/legal/latest/alibaba-cloud-international-website-privacy-policy
- Trust Center: https://www.alibabacloud.com/en/trust-center/faq

## Cómo usarlos desde el Claude Code CLI

### Opción 1 — Cambiar de modelo en la sesión (más fácil)
Dentro del CLI, usa el comando slash con el ID exacto:

```
/model glm-5.3
/model deepseek-v4-pro
/model kimi-k3
```

Para volver a Qwen:

```
/model qwen3.8-max
```

### Opción 2 — Al arrancar el CLI

```bash
claude --model kimi-k3
```

### Opción 3 — Variable de entorno (para dejarlo fijo)

```bash
ANTHROPIC_MODEL=glm-5.3 claude
```

### Opción 4 — Como modelo de subagentes

```bash
CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-pro claude
```

## Cómo probarlos fuera del CLI

### curl (formato Anthropic, misma ruta que usa el CLI)

```bash
curl -s "$ANTHROPIC_BASE_URL/v1/messages" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5.3",
    "max_tokens": 2000,
    "messages": [{"role": "user", "content": "di hola brevemente"}]
  }' | python3 -m json.tool
```

### curl (formato OpenAI)

```bash
BASE="${ANTHROPIC_BASE_URL%/apps/anthropic}/compatible-mode/v1"

curl -s "$BASE/chat/completions" \
  -H "Authorization: Bearer $ANTHROPIC_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kimi-k3",
    "max_tokens": 2000,
    "messages": [{"role": "user", "content": "di hola brevemente"}]
  }' | python3 -m json.tool
```

### Python con el SDK de OpenAI

```python
import os
from openai import OpenAI

client = OpenAI(
    api_key=os.environ["ANTHROPIC_API_KEY"],
    base_url=os.environ["ANTHROPIC_BASE_URL"].replace("/apps/anthropic", "")
             + "/compatible-mode/v1",
)

for modelo in ["deepseek-v4-pro", "glm-5.3", "kimi-k3"]:
    r = client.chat.completions.create(
        model=modelo,
        messages=[{"role": "user", "content": "¿Cuál es 17 * 23? Responde solo con el número."}],
        max_tokens=2000,
    )
    print(f"== {modelo} ==")
    print("respuesta:", r.choices[0].message.content)
    print("tokens:", r.usage.total_tokens)
```

## Listar todos los modelos disponibles (102 en total)

```bash
curl -s "${ANTHROPIC_BASE_URL%/apps/anthropic}/compatible-mode/v1/models" \
  -H "Authorization: Bearer $ANTHROPIC_API_KEY" | python3 -c "
import json, sys
for m in json.load(sys.stdin)['data']:
    print(m['id'])" | sort
```
