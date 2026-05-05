import * as React from "react";
import { cn } from "../../lib/utils";

type DivProps = React.ComponentProps<"div">;

export function Card({ className, ...props }: DivProps) {
  return (
    <div
      className={cn(
        "rounded-lg border border-border bg-card text-card-foreground shadow",
        className,
      )}
      {...props}
    />
  );
}

export function CardHeader({ className, ...props }: DivProps) {
  return (
    <div className={cn("flex flex-col space-y-1 p-6", className)} {...props} />
  );
}

export function CardTitle({ className, ...props }: DivProps) {
  return (
    <div
      className={cn("text-xl font-semibold tracking-tight", className)}
      {...props}
    />
  );
}

export function CardContent({ className, ...props }: DivProps) {
  return <div className={cn("p-6 pt-0", className)} {...props} />;
}
