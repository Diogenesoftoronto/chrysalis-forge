/** @type {import('tailwindcss').Config} */
export default {
  darkMode: "class",
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    container: {
      center: true,
      padding: "1rem",
      screens: { "2xl": "1100px" },
    },
    extend: {
      colors: {
        border: "hsl(240 10% 14%)",
        input: "hsl(240 10% 14%)",
        ring: "hsl(265 85% 75%)",
        background: "hsl(240 18% 5%)",
        foreground: "hsl(240 10% 92%)",
        primary: {
          DEFAULT: "hsl(265 85% 75%)",
          foreground: "hsl(240 18% 8%)",
        },
        secondary: {
          DEFAULT: "hsl(240 10% 12%)",
          foreground: "hsl(240 10% 92%)",
        },
        muted: {
          DEFAULT: "hsl(240 10% 12%)",
          foreground: "hsl(240 8% 62%)",
        },
        accent: {
          DEFAULT: "hsl(240 10% 14%)",
          foreground: "hsl(240 10% 92%)",
        },
        destructive: {
          DEFAULT: "hsl(0 72% 55%)",
          foreground: "hsl(0 0% 98%)",
        },
        card: {
          DEFAULT: "hsl(240 15% 7%)",
          foreground: "hsl(240 10% 92%)",
        },
      },
      borderRadius: {
        lg: "0.625rem",
        md: "0.5rem",
        sm: "0.375rem",
      },
      keyframes: {
        "accordion-down": {
          from: { height: "0" },
          to: { height: "var(--radix-accordion-content-height)" },
        },
        "accordion-up": {
          from: { height: "var(--radix-accordion-content-height)" },
          to: { height: "0" },
        },
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};
