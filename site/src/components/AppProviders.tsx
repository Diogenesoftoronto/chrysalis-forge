import type { ReactNode } from "react";
import {
  Client as StyletronClient,
  Server as StyletronServer,
} from "styletron-engine-atomic";
import { Provider as StyletronProvider } from "styletron-react";
import { BaseProvider } from "baseui";
import { chrysalisTheme } from "../lib/chrysalis-theme";

const styletron =
  typeof document === "undefined" ? new StyletronServer() : new StyletronClient();

export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <StyletronProvider value={styletron}>
      <BaseProvider theme={chrysalisTheme} zIndex={3000}>
        {children}
      </BaseProvider>
    </StyletronProvider>
  );
}
