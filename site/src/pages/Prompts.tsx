import ReactMarkdown from "react-markdown";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";
import { prompts } from "../lib/piContent";

export default function Prompts() {
  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-3xl font-bold tracking-tight">Task prompts</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Source of truth lives in <code className="text-primary">pi/prompts/</code>.
        </p>
      </header>
      <div className="space-y-4">
        {prompts.map((p) => (
          <Card key={p.id}>
            <CardHeader>
              <CardTitle>{p.title}</CardTitle>
            </CardHeader>
            <CardContent className="prose prose-invert max-w-none text-sm text-muted-foreground">
              <ReactMarkdown>{p.body}</ReactMarkdown>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
