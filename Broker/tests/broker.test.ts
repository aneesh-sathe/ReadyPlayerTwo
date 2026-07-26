import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { startBroker } from "../src/broker.ts";

test("binds only to loopback and reports health", async (context) => {
  const broker = await startBroker({
    apiKey: undefined,
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
  });
  context.after(() => broker.close());

  assert.equal(broker.address.host, "127.0.0.1");

  const response = await fetch(`${broker.origin}/health`);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "ok",
    voice: "not_configured",
  });
});

test("requires the per-launch bearer for client secrets", async (context) => {
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    { method: "POST" },
  );

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "unauthorized" });
});

test("redacts missing API key details", async (context) => {
  const broker = await startBroker({
    apiKey: undefined,
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    {
      headers: {
        authorization: "Bearer test-launch-bearer",
      },
      method: "POST",
    },
  );
  const responseText = await response.text();

  assert.equal(response.status, 503);
  assert.equal(responseText, '{"error":"voice_not_configured"}');
  assert.doesNotMatch(
    responseText,
    /OPENAI_API_KEY|api.?key|test-launch-bearer/i,
  );
});

test("requests a client secret with only allowlisted session config", async (context) => {
  const upstreamRequests: Array<{
    body: unknown;
    headers: Headers;
    method: string;
    url: string;
  }> = [];
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async (input, init) => {
      upstreamRequests.push({
        body: JSON.parse(String(init?.body)),
        headers: new Headers(init?.headers),
        method: init?.method ?? "GET",
        url: String(input),
      });
      return Response.json({
        expires_at: 1_900_000_000,
        value: "ek_short_lived_secret",
      });
    },
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    {
      body: JSON.stringify({
        model: "gpt-realtime-2.1",
        voice: "marin",
      }),
      headers: {
        authorization: "Bearer test-launch-bearer",
        "content-type": "application/json",
      },
      method: "POST",
    },
  );

  assert.equal(response.status, 200);
  assert.equal(upstreamRequests.length, 1);
  assert.deepEqual(upstreamRequests[0], {
    body: {
      session: {
        audio: {
          output: {
            voice: "marin",
          },
        },
        model: "gpt-realtime-2.1",
        type: "realtime",
      },
    },
    headers: new Headers({
      authorization: "Bearer sk-standard-secret",
      "content-type": "application/json",
      "openai-safety-identifier": "local-test-user",
    }),
    method: "POST",
    url: "https://api.openai.com/v1/realtime/client_secrets",
  });
});

test("accepts and forwards every approved V1 voice", async (context) => {
  const approvedVoices = [
    "alloy",
    "ash",
    "ballad",
    "coral",
    "echo",
    "sage",
    "shimmer",
    "verse",
    "marin",
    "cedar",
  ];
  const upstreamVoices: string[] = [];
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async (_input, init) => {
      const body = JSON.parse(String(init?.body)) as {
        session: {
          audio: {
            output: {
              voice: string;
            };
          };
        };
      };
      upstreamVoices.push(body.session.audio.output.voice);
      return Response.json({
        expires_at: 1_900_000_000,
        value: "ek_short_lived_secret",
      });
    },
  });
  context.after(() => broker.close());

  for (const voice of approvedVoices) {
    const response = await fetch(
      `${broker.origin}/v1/realtime/client-secret`,
      {
        body: JSON.stringify({
          model: "gpt-realtime-2.1",
          voice,
        }),
        headers: {
          authorization: "Bearer test-launch-bearer",
          "content-type": "application/json",
        },
        method: "POST",
      },
    );

    assert.equal(response.status, 200, voice);
  }
  assert.deepEqual(upstreamVoices, approvedVoices);
});

test("returns only the short-lived client secret fields", async (context) => {
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async () =>
      Response.json({
        expires_at: 1_900_000_000,
        internal_trace: "must-not-cross-boundary",
        session: {
          instructions: "must-not-cross-boundary",
        },
        value: "ek_short_lived_secret",
      }),
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    {
      headers: {
        authorization: "Bearer test-launch-bearer",
      },
      method: "POST",
    },
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {
    expires_at: 1_900_000_000,
    value: "ek_short_lived_secret",
  });
});

test("rejects model and voice values outside the V1 allowlist", async (context) => {
  let upstreamRequestCount = 0;
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async () => {
      upstreamRequestCount += 1;
      return Response.json({
        expires_at: 1_900_000_000,
        value: "ek_short_lived_secret",
      });
    },
  });
  context.after(() => broker.close());

  const rejectedConfigurations = [
    {
      model: "unapproved-model",
      voice: "marin",
    },
    {
      model: "gpt-realtime-2.1",
      voice: "unapproved-voice",
    },
  ];

  for (const configuration of rejectedConfigurations) {
    const response = await fetch(
      `${broker.origin}/v1/realtime/client-secret`,
      {
        body: JSON.stringify(configuration),
        headers: {
          authorization: "Bearer test-launch-bearer",
          "content-type": "application/json",
        },
        method: "POST",
      },
    );

    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {
      error: "configuration_not_allowed",
    });
  }
  assert.equal(upstreamRequestCount, 0);
});

test("classifies and redacts upstream authentication failures", async (context) => {
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async () =>
      Response.json(
        {
          error: {
            message:
              "Rejected sk-standard-secret for test-launch-bearer",
          },
        },
        { status: 401 },
      ),
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    {
      headers: {
        authorization: "Bearer test-launch-bearer",
      },
      method: "POST",
    },
  );
  const responseText = await response.text();

  assert.equal(response.status, 401);
  assert.equal(
    responseText,
    '{"error":"upstream_authentication_failed"}',
  );
  assert.doesNotMatch(
    responseText,
    /sk-standard-secret|test-launch-bearer|rejected/i,
  );
});

test("classifies and redacts upstream rate limits", async (context) => {
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async () =>
      Response.json(
        {
          error: {
            message:
              "Rejected sk-standard-secret for test-launch-bearer",
          },
        },
        { status: 429 },
      ),
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    {
      headers: {
        authorization: "Bearer test-launch-bearer",
      },
      method: "POST",
    },
  );
  const responseText = await response.text();

  assert.equal(response.status, 429);
  assert.equal(responseText, '{"error":"upstream_rate_limited"}');
  assert.doesNotMatch(
    responseText,
    /sk-standard-secret|test-launch-bearer|rejected/i,
  );
});

test("redacts unclassified upstream failures", async (context) => {
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async () =>
      Response.json(
        {
          error: {
            message:
              "Provider leaked sk-standard-secret in an error",
          },
        },
        { status: 500 },
      ),
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    {
      headers: {
        authorization: "Bearer test-launch-bearer",
      },
      method: "POST",
    },
  );
  const responseText = await response.text();

  assert.equal(response.status, 502);
  assert.equal(responseText, '{"error":"upstream_unavailable"}');
  assert.doesNotMatch(
    responseText,
    /sk-standard-secret|provider|leaked/i,
  );
});

test("redacts upstream network errors", async (context) => {
  const broker = await startBroker({
    apiKey: "sk-standard-secret",
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
    upstreamFetch: async () => {
      throw new Error(
        "Network failure exposed sk-standard-secret and local-test-user",
      );
    },
  });
  context.after(() => broker.close());

  const response = await fetch(
    `${broker.origin}/v1/realtime/client-secret`,
    {
      headers: {
        authorization: "Bearer test-launch-bearer",
      },
      method: "POST",
    },
  );
  const responseText = await response.text();

  assert.equal(response.status, 502);
  assert.equal(responseText, '{"error":"upstream_unavailable"}');
  assert.doesNotMatch(
    responseText,
    /sk-standard-secret|local-test-user|network failure/i,
  );
});

test("closes cleanly and idempotently", async () => {
  const broker = await startBroker({
    apiKey: undefined,
    bearerToken: "test-launch-bearer",
    safetyIdentifier: "local-test-user",
  });

  await broker.close();
  await broker.close();

  await assert.rejects(fetch(`${broker.origin}/health`), TypeError);
});

test("the executable logs only redacted lifecycle events", async () => {
  const mainPath = fileURLToPath(
    new URL("../src/main.ts", import.meta.url),
  );
  const child = spawn(process.execPath, [mainPath], {
    env: {
      ...process.env,
      OPENAI_API_KEY: "sk-standard-secret",
      READYPLAYERTWO_BROKER_BEARER: "test-launch-bearer",
      READYPLAYERTWO_OPENAI_SAFETY_IDENTIFIER: "local-test-user",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let standardOutput = "";
  let standardError = "";
  let didRequestClose = false;

  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    standardOutput += chunk;
    if (
      !didRequestClose &&
      standardOutput.includes('"event":"broker_listening"')
    ) {
      didRequestClose = true;
      child.kill("SIGTERM");
    }
  });
  child.stderr.on("data", (chunk: string) => {
    standardError += chunk;
  });

  const exitCode = await new Promise<number | null>((resolve, reject) => {
    const timeout = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error("broker executable did not close"));
    }, 3_000);
    child.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.once("exit", (code) => {
      clearTimeout(timeout);
      resolve(code);
    });
  });

  assert.equal(exitCode, 0);
  assert.equal(standardError, "");
  assert.doesNotMatch(
    standardOutput,
    /sk-standard-secret|test-launch-bearer|local-test-user/,
  );
  assert.match(standardOutput, /"event":"broker_listening"/);
  assert.match(standardOutput, /"host":"127\.0\.0\.1"/);
  assert.match(standardOutput, /"event":"broker_closed"/);
});
