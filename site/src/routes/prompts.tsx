import { createFileRoute } from "@tanstack/react-router";
import Prompts from "../pages/Prompts";

export const Route = createFileRoute("/prompts")({
  component: Prompts,
});
