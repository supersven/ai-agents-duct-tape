{ }:
{
  config.opencode.provider.cloud-temple = {
    npm = "@ai-sdk/openai-compatible";
    name = "Cloud Temple";
    options.baseURL = "https://api.ai.cloud-temple.com/v1";
    options.apiKey = "{env:CLOUD_TEMPLE_API_TOKEN}";
    models = (import ./generated/cloud-temple-models.nix).models;
  };
}
