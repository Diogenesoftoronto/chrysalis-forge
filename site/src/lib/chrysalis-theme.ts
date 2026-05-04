import { createDarkTheme } from "baseui";

/** Dark theme aligned with the previous Tailwind palette (purple accent, near-black surfaces). */
export const chrysalisTheme = createDarkTheme({
  colors: {
    backgroundPrimary: "hsl(240 18% 5%)",
    backgroundSecondary: "hsl(240 15% 7%)",
    backgroundTertiary: "hsl(240 10% 12%)",
    contentPrimary: "hsl(240 10% 92%)",
    contentSecondary: "hsl(240 8% 62%)",
    contentTertiary: "hsl(240 8% 50%)",
    borderOpaque: "hsl(240 10% 14%)",
    accent: "hsl(265 85% 75%)",
    contentAccent: "hsl(265 85% 75%)",
    buttonPrimaryFill: "hsl(265 85% 75%)",
    buttonPrimaryText: "hsl(240 18% 8%)",
    buttonPrimaryHover: "hsl(265 75% 68%)",
    buttonPrimaryActive: "hsl(265 70% 58%)",
    negative: "hsl(0 72% 55%)",
    contentNegative: "hsl(0 72% 62%)",
    warning: "hsl(45 90% 55%)",
    contentWarning: "hsl(45 90% 60%)",
    contentPositive: "hsl(142 70% 48%)",
  },
});
