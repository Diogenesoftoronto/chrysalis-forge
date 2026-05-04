import { useStyletron } from "baseui";
import { Card } from "baseui/card";
import { HeadingLarge, ParagraphSmall } from "baseui/typography";
import { MarkdownBody } from "../components/MarkdownBody";
import { prompts } from "../lib/piContent";

export default function Prompts() {
  const [css, theme] = useStyletron();
  return (
    <div className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale600 })}>
      <header>
        <HeadingLarge marginTop={0} marginBottom={theme.sizing.scale300}>
          Task prompts
        </HeadingLarge>
        <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
          Source of truth lives in <code className={css({ color: theme.colors.accent })}>pi/prompts/</code>.
        </ParagraphSmall>
      </header>
      <div className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale500 })}>
        {prompts.map((p) => (
          <Card key={p.id} overrides={{}} title={p.title}>
            <MarkdownBody>{p.body}</MarkdownBody>
          </Card>
        ))}
      </div>
    </div>
  );
}
