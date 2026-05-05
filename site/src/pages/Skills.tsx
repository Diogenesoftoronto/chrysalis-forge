import ReactMarkdown from "react-markdown";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";
import { skills, stripFrontmatter } from "../lib/piContent";

export default function Skills() {
  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-3xl font-bold tracking-tight">Skills</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Source of truth lives in <code className="text-primary">pi/skills/</code>.
        </p>
      </header>
      <div className="space-y-4">
        {skills.map((s) => (
          <Card key={s.id}>
            <CardHeader>
              <CardTitle>{s.title}</CardTitle>
            </CardHeader>
            <CardContent className="prose prose-invert max-w-none text-sm text-muted-foreground">
              <ReactMarkdown>{stripFrontmatter(s.body)}</ReactMarkdown>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
