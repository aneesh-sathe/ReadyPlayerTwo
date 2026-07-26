import { createHash, timingSafeEqual } from "node:crypto";
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import type { AddressInfo } from "node:net";

const LOOPBACK_HOST = "127.0.0.1";
const REALTIME_CLIENT_SECRETS_URL =
  "https://api.openai.com/v1/realtime/client_secrets";
const V1_MODEL = "gpt-realtime-2.1";
const V1_VOICE = "marin";

export interface StartBrokerOptions {
  apiKey: string | undefined;
  bearerToken: string;
  safetyIdentifier: string;
  upstreamFetch?: typeof fetch;
}

export interface BrokerHandle {
  address: {
    host: string;
    port: number;
  };
  origin: string;
  close(): Promise<void>;
}

export async function startBroker(
  options: StartBrokerOptions,
): Promise<BrokerHandle> {
  const server = createServer((request, response) => {
    void handleRequest(request, response, options).catch(() => {
      if (!response.headersSent) {
        sendJson(response, 502, { error: "upstream_unavailable" });
        return;
      }
      response.destroy();
    });
  });

  const address = await listenOnLoopback(server);

  return {
    address: {
      host: address.address,
      port: address.port,
    },
    origin: `http://${address.address}:${address.port}`,
    close: () => closeServer(server),
  };
}

async function handleRequest(
  request: IncomingMessage,
  response: ServerResponse,
  options: StartBrokerOptions,
): Promise<void> {
  if (request.method === "GET" && request.url === "/health") {
    sendJson(response, 200, {
      status: "ok",
      voice: options.apiKey ? "configured" : "not_configured",
    });
    return;
  }

  if (
    request.method !== "POST" ||
    request.url !== "/v1/realtime/client-secret"
  ) {
    sendJson(response, 404, { error: "not_found" });
    return;
  }

  if (!hasValidBearer(request.headers.authorization, options.bearerToken)) {
    sendJson(response, 401, { error: "unauthorized" });
    return;
  }

  if (!options.apiKey) {
    sendJson(response, 503, { error: "voice_not_configured" });
    return;
  }

  const requestedConfig = await readRequestedConfig(request);
  if (
    requestedConfig.model !== V1_MODEL ||
    requestedConfig.voice !== V1_VOICE
  ) {
    sendJson(response, 400, { error: "configuration_not_allowed" });
    return;
  }

  const upstreamResponse = await (options.upstreamFetch ?? fetch)(
    REALTIME_CLIENT_SECRETS_URL,
    {
      body: JSON.stringify({
        session: {
          audio: {
            output: {
              voice: V1_VOICE,
            },
          },
          model: V1_MODEL,
          type: "realtime",
        },
      }),
      headers: {
        authorization: `Bearer ${options.apiKey}`,
        "content-type": "application/json",
        "OpenAI-Safety-Identifier": options.safetyIdentifier,
      },
      method: "POST",
    },
  );
  if (!upstreamResponse.ok) {
    if (
      upstreamResponse.status === 401 ||
      upstreamResponse.status === 403
    ) {
      sendJson(response, 401, {
        error: "upstream_authentication_failed",
      });
      return;
    }
    if (upstreamResponse.status === 429) {
      sendJson(response, 429, {
        error: "upstream_rate_limited",
      });
      return;
    }
    sendJson(response, 502, { error: "upstream_unavailable" });
    return;
  }

  const upstreamBody = (await upstreamResponse.json()) as {
    expires_at?: unknown;
    value?: unknown;
  };
  if (
    typeof upstreamBody.expires_at !== "number" ||
    typeof upstreamBody.value !== "string"
  ) {
    sendJson(response, 502, { error: "upstream_unavailable" });
    return;
  }

  sendJson(response, 200, {
    expires_at: upstreamBody.expires_at,
    value: upstreamBody.value,
  });
}

async function readRequestedConfig(
  request: IncomingMessage,
): Promise<{ model: string; voice: string }> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  const body = chunks.length
    ? (JSON.parse(Buffer.concat(chunks).toString("utf8")) as {
        model?: unknown;
        voice?: unknown;
      })
    : {};

  return {
    model: body.model === undefined ? V1_MODEL : String(body.model),
    voice: body.voice === undefined ? V1_VOICE : String(body.voice),
  };
}

function hasValidBearer(
  authorization: string | undefined,
  expectedToken: string,
): boolean {
  const prefix = "Bearer ";
  if (!authorization?.startsWith(prefix)) {
    return false;
  }

  const actualDigest = createHash("sha256")
    .update(authorization.slice(prefix.length))
    .digest();
  const expectedDigest = createHash("sha256").update(expectedToken).digest();
  return timingSafeEqual(actualDigest, expectedDigest);
}

function listenOnLoopback(server: Server): Promise<AddressInfo> {
  return new Promise((resolve, reject) => {
    const onError = (error: Error) => {
      server.off("listening", onListening);
      reject(error);
    };
    const onListening = () => {
      server.off("error", onError);
      resolve(server.address() as AddressInfo);
    };

    server.once("error", onError);
    server.once("listening", onListening);
    server.listen({
      exclusive: true,
      host: LOOPBACK_HOST,
      port: 0,
    });
  });
}

function closeServer(server: Server): Promise<void> {
  if (!server.listening) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

function sendJson(
  response: ServerResponse,
  status: number,
  body: unknown,
): void {
  response.writeHead(status, {
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify(body));
}
