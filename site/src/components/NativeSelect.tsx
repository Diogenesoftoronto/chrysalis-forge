import type { ComponentProps } from "react";
import { useStyletron } from "baseui";

export type NativeSelectProps = ComponentProps<"select">;

/** Native &lt;select&gt; styled with Base Web theme tokens (Styletron). */
export function NativeSelect({ className, ...props }: NativeSelectProps) {
  const [css, theme] = useStyletron();
  const styles = css({
    boxSizing: "border-box",
    height: theme.sizing.scale800,
    minWidth: "160px",
    paddingLeft: theme.sizing.scale400,
    paddingRight: theme.sizing.scale400,
    borderTopLeftRadius: theme.borders.radius200,
    borderTopRightRadius: theme.borders.radius200,
    borderBottomLeftRadius: theme.borders.radius200,
    borderBottomRightRadius: theme.borders.radius200,
    borderWidth: "1px",
    borderStyle: "solid",
    borderColor: theme.colors.borderOpaque,
    backgroundColor: theme.colors.backgroundSecondary,
    color: theme.colors.contentPrimary,
    fontSize: theme.typography.font200.fontSize,
    outline: "none",
    cursor: "pointer",
  });
  return <select {...props} className={[styles, className].filter(Boolean).join(" ")} />;
}
