import { useStyletron } from "baseui";
import { Card } from "baseui/card";
import { HeadingLarge, ParagraphSmall } from "baseui/typography";
import { MarkdownBody } from "../components/MarkdownBody";
import { skills, stripFrontmatter } from "../lib/piContent";

export default function Skills() {
  const [css, theme] = useStyletron();
  return (
    <div className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale600 })}>
      <header>
        <HeadingLarge marginTop={0} marginBottom={theme.sizing.scale300}>
          Skills
        </HeadingLarge>
        <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
          Source of truth lives in <code className={css({ color: theme.colors.accent })}>pi/skills/</code>.
        </ParagraphSmall>
      </header>
      <div className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale500 })}>
        {skills.map((s) => (
          <Card key={s.id} overrides={{}} title={s.title}>
            <MarkdownBody>{stripFrontmatter(s.body)}</MarkdownBody>
          </Card>
        ))}
      </div>
    </div>
  );
}
