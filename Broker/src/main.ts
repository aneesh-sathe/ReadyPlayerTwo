import { startBroker } from "./broker.ts";

const bearerToken = process.env.READYPLAYERTWO_BROKER_BEARER;
const safetyIdentifier =
  process.env.READYPLAYERTWO_OPENAI_SAFETY_IDENTIFIER;

if (!bearerToken || !safetyIdentifier) {
  writeEvent("broker_configuration_invalid");
  process.exitCode = 1;
} else {
  void run({
    apiKey: process.env.OPENAI_API_KEY,
    bearerToken,
    safetyIdentifier,
  });
}

async function run(options: {
  apiKey: string | undefined;
  bearerToken: string;
  safetyIdentifier: string;
}): Promise<void> {
  try {
    const broker = await startBroker(options);
    let isClosing = false;
    const close = async (signal: "SIGINT" | "SIGTERM") => {
      if (isClosing) {
        return;
      }
      isClosing = true;

      try {
        await broker.close();
        writeEvent("broker_closed", { signal });
      } catch {
        writeEvent("broker_close_failed", { signal });
        process.exitCode = 1;
      }
    };

    process.once("SIGINT", () => void close("SIGINT"));
    process.once("SIGTERM", () => void close("SIGTERM"));
    writeEvent("broker_listening", {
      host: broker.address.host,
      port: broker.address.port,
      voice: options.apiKey ? "configured" : "not_configured",
    });
  } catch {
    writeEvent("broker_start_failed");
    process.exitCode = 1;
  }
}

function writeEvent(
  event: string,
  details: Record<string, number | string> = {},
): void {
  process.stdout.write(`${JSON.stringify({ event, ...details })}\n`);
}
