// Amazon Bedrock models
export const DEFAULT_CHAT_MODEL = "amazon.nova-lite-v1:0";

export type ChatModel = {
  id: string;
  name: string;
  provider: string;
  description: string;
};

export const chatModels: ChatModel[] = [
  // Anthropic via Bedrock - Claude 4.5 (using inference profiles)
  {
    id: "us.anthropic.claude-3-5-haiku-20241022-v1:0",
    name: "Claude 3.5 Haiku",
    provider: "anthropic",
    description: "Fast and affordable, great for everyday tasks",
  },
  {
    id: "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
    name: "Claude 3.5 Sonnet",
    provider: "anthropic",
    description: "Best balance of speed, intelligence, and cost",
  },
  // Amazon Nova
  {
    id: "amazon.nova-lite-v1:0",
    name: "Amazon Nova Lite",
    provider: "amazon",
    description: "Fast and cost-effective for simple tasks",
  },
  {
    id: "amazon.nova-pro-v1:0",
    name: "Amazon Nova Pro",
    provider: "amazon",
    description: "Capable Amazon model for complex tasks",
  },
];

// Group models by provider for UI
export const modelsByProvider = chatModels.reduce(
  (acc, model) => {
    if (!acc[model.provider]) {
      acc[model.provider] = [];
    }
    acc[model.provider].push(model);
    return acc;
  },
  {} as Record<string, ChatModel[]>
);
