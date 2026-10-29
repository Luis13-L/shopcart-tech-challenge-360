
import { createApp } from "./app.js";
import { env } from "./config/env.js";

const app = createApp();

app.listen(env.PORT, () => {
  console.log(
    `ShopCart API disponible en http://localhost:${env.PORT}`
  );

  console.log(`Entorno: ${env.NODE_ENV}`);
});
