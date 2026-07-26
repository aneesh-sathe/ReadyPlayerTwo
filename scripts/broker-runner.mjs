import { writeFile } from "node:fs/promises";

import { startBroker } from "../Broker/src/broker.ts";

const bearerToken = process.env.RPT_BROKER_BEARER_TOKEN;
const runtimeConfigPath = process.env.RPT_RUNTIME_CONFIG_PATH;
const safetyIdentifier = process.env.RPT_SAFETY_IDENTIFIER;

if (!bearerToken || !runtimeConfigPath || !safetyIdentifier) {
  process.stderr.write("Broker runtime configuration is incomplete.\n");
  process.exit(1);
}

let broker;
try {
  broker = await startBroker({
    apiKey: process.env.OPENAI_API_KEY,
    bearerToken,
    safetyIdentifier,
  });

  await writeFile(
    runtimeConfigPath,
    `${JSON.stringify({
      brokerBaseURL: broker.origin,
      brokerBearerToken: bearerToken,
      schemaVersion: 1,
    })}\n`,
    {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    },
  );
} catch {
  process.stderr.write("Broker failed to start.\n");
  process.exit(1);
}

let closing = false;
async function close(exitCode) {
  if (closing) {
    return;
  }
  closing = true;
  try {
    await broker.close();
  } finally {
    process.exit(exitCode);
  }
}

process.on("SIGINT", () => {
  void close(130);
});
process.on("SIGTERM", () => {
  void close(143);
});

await new Promise(() => {});
