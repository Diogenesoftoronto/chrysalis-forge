import type { ComponentProps } from "react";

export type NativeSelectProps = ComponentProps<"select">;

export function NativeSelect({ className, ...props }: NativeSelectProps) {
  return (
    <select
      className={[
        "box-border h-10 min-w-[160px] cursor-pointer border border-border bg-bg2 px-3 text-sm text-foreground outline-none",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
      {...props}
    />
  );
}
