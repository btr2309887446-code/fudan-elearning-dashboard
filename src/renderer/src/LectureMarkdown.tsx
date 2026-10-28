import { useMemo } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import "katex/dist/katex.min.css";
const messageOf = (error: unknown) => error instanceof Error ? error.message : String(error);
export default function LectureMarkdown({ text, onError }: { text: string; onError: (value: string) => void }) {
  const content = useMemo(() => text.replace(/\\\[([\s\S]*?)\\\]/g, (_, math) => `$$${math}$$`).replace(/\\\((.*?)\\\)/g, (_, math) => `$${math}$`), [text]);
  return <ReactMarkdown skipHtml remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[[rehypeKatex, { trust: false, throwOnError: false, strict: false }]]}
    components={{
      h1: ({ node, children }) => <h2 id={`cc-heading-${node?.position?.start.line}`}>{children}</h2>,
      h2: ({ node, children }) => <h2 id={`cc-heading-${node?.position?.start.line}`}>{children}</h2>,
      h3: ({ node, children }) => <h3 id={`cc-heading-${node?.position?.start.line}`}>{children}</h3>,
      h4: ({ node, children }) => <h4 id={`cc-heading-${node?.position?.start.line}`}>{children}</h4>,
      h5: ({ node, children }) => <h5 id={`cc-heading-${node?.position?.start.line}`}>{children}</h5>,
      h6: ({ node, children }) => <h6 id={`cc-heading-${node?.position?.start.line}`}>{children}</h6>,
      a: ({ href, children }) => href && /^https:\/\//i.test(href) ? <a href={href} onClick={event => { event.preventDefault(); void window.elearning.open(href).catch(error => onError(messageOf(error))); }}>{children}</a> : <span>{children}</span>,
      img: ({ alt }) => <span className="cc-muted">〔{alt || "图片"}〕</span>,
      table: ({ children }) => <div className="cc-table-scroll" tabIndex={0} role="region" aria-label="表格，可横向滚动"><table>{children}</table></div>,
    }}>{content}</ReactMarkdown>;
}
