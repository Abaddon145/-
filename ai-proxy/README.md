# KoreanMemo AI proxy

Node.js >=22，TypeScript + ESM，独立部署。使用官方 OpenAI SDK 和 p-queue，模型与输出能力通过环境变量配置。

完整部署、API、配置、使用和数据边界见 [AI 部署说明](../docs/ai-deployment.md)。测试不访问真实模型。

```sh
npm ci
cp .env.example .env
# Fill configuration before starting.
npm run check
npm test
npm run build
npm start
```
