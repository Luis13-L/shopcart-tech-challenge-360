import { Router } from "express";

import {
  getCatalogProducts
} from "./catalog.controller.js";

export const catalogRouter = Router();

catalogRouter.get("/", getCatalogProducts);
