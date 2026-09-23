import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Say hello to the world",
  args: { name: tool.schema.string() },
  async execute(args) {
    return `hello ${args.name}`
  },
})
