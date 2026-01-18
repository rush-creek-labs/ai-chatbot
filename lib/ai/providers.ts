import { createAmazonBedrock } from "@ai-sdk/amazon-bedrock";
import { fromContainerMetadata, fromEnv } from "@aws-sdk/credential-providers";
import { customProvider } from "ai";
import { isTestEnvironment } from "../constants";

// Create Bedrock provider with explicit credential chain for ECS
const bedrock = createAmazonBedrock({
  region: process.env.AWS_REGION || "us-east-1",
  credentialProvider: async () => {
    // Try container credentials first (ECS), then fall back to env vars (local dev)
    try {
      return await fromContainerMetadata()();
    } catch {
      return await fromEnv()();
    }
  },
});

export const myProvider = isTestEnvironment
  ? (() => {
      const {
        artifactModel,
        chatModel,
        reasoningModel,
        titleModel,
      } = require("./models.mock");
      return customProvider({
        languageModels: {
          "chat-model": chatModel,
          "chat-model-reasoning": reasoningModel,
          "title-model": titleModel,
          "artifact-model": artifactModel,
        },
      });
    })()
  : null;

export function getLanguageModel(modelId: string) {
  if (isTestEnvironment && myProvider) {
    return myProvider.languageModel(modelId);
  }

  return bedrock(modelId);
}

export function getTitleModel() {
  if (isTestEnvironment && myProvider) {
    return myProvider.languageModel("title-model");
  }
  return bedrock("amazon.nova-lite-v1:0");
}

export function getArtifactModel() {
  if (isTestEnvironment && myProvider) {
    return myProvider.languageModel("artifact-model");
  }
  return bedrock("us.anthropic.claude-3-5-haiku-20241022-v1:0");
}
