import { Router } from "express";
import { getDatabaseHealth } from "./system.controller.js";

export const systemRouter = Router();

systemRouter.get("/db", getDatabaseHealth);