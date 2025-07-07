import * as fs from "node:fs";
import * as path from "node:path";

const SUPPORTED_LANGUAGES = ['en', 'es', 'ja', 'ko', 'pt', 'ru'];

/**
 * Validates LocalizedLink href values during build time
 */
export class LocalizedLinkValidator {
  constructor(srcDir) {
    this.srcDir = srcDir;
    this.linkRegistry = new Map();
    this.brokenLinks = [];
    this.validatedLinks = new Set();
  }

  /**
   * Scans all markdown files and extracts LocalizedLink href values
   */
  async scanFiles() {
    console.log('🔍 Scanning files for LocalizedLink components...');
    
    for (const lang of SUPPORTED_LANGUAGES) {
      const langDir = path.join(this.srcDir, lang);
      if (fs.existsSync(langDir)) {
        await this.scanDirectory(langDir, lang);
      }
    }
    
    console.log(`📊 Found ${this.linkRegistry.size} unique LocalizedLink references`);
  }

  /**
   * Recursively scans a directory for markdown files
   */
  async scanDirectory(dir, lang) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      
      if (entry.isDirectory()) {
        await this.scanDirectory(fullPath, lang);
      } else if (entry.isFile() && entry.name.endsWith('.md')) {
        await this.scanFile(fullPath, lang);
      }
    }
  }

  /**
   * Scans a markdown file for LocalizedLink components
   */
  async scanFile(filePath, lang) {
    const content = fs.readFileSync(filePath, 'utf8');
    const localizedLinkRegex = /<LocalizedLink\s+href="([^"]+)"/g;
    
    let match;
    while ((match = localizedLinkRegex.exec(content)) !== null) {
      const href = match[1];
      
      if (!this.linkRegistry.has(href)) {
        this.linkRegistry.set(href, []);
      }
      
      this.linkRegistry.get(href).push({
        file: filePath,
        lang: lang
      });
    }
  }

  /**
   * Validates all collected links
   */
  async validateLinks() {
    console.log('✅ Validating LocalizedLink href values...');
    
    for (const [href, occurrences] of this.linkRegistry) {
      const isValid = await this.validateLink(href);
      
      if (!isValid) {
        this.brokenLinks.push({
          href,
          occurrences
        });
      }
    }
    
    if (this.brokenLinks.length > 0) {
      console.error(`❌ Found ${this.brokenLinks.length} broken LocalizedLink references:`);
      
      for (const { href, occurrences } of this.brokenLinks) {
        console.error(`\n🔗 Broken link: ${href}`);
        console.error(`   Used in ${occurrences.length} file(s):`);
        
        for (const { file, lang } of occurrences) {
          const relativePath = path.relative(this.srcDir, file);
          console.error(`   - [${lang}] ${relativePath}`);
        }
        
        // Suggest corrections
        const suggestion = this.suggestCorrection(href);
        if (suggestion) {
          console.error(`   💡 Suggested fix: ${suggestion}`);
        }
      }
      
      throw new Error(`Build failed: ${this.brokenLinks.length} broken LocalizedLink references found`);
    } else {
      console.log('✅ All LocalizedLink references are valid!');
    }
  }

  /**
   * Validates a single link href
   */
  async validateLink(href) {
    if (this.validatedLinks.has(href)) {
      return true;
    }

    // Remove anchor if present
    const [pathPart] = href.split('#');
    
    // Special handling for dynamic routes
    if (this.isDynamicRoute(pathPart)) {
      return this.validateDynamicRoute(pathPart);
    }
    
    // Check if file exists in any language
    for (const lang of SUPPORTED_LANGUAGES) {
      const fullPath = path.join(this.srcDir, lang, pathPart);
      const mdPath = fullPath.endsWith('.md') ? fullPath : `${fullPath}.md`;
      
      if (fs.existsSync(mdPath)) {
        this.validatedLinks.add(href);
        return true;
      }
      
      // Also check for index.md in directory
      const indexPath = path.join(fullPath, 'index.md');
      if (fs.existsSync(indexPath)) {
        this.validatedLinks.add(href);
        return true;
      }
    }
    
    return false;
  }

  /**
   * Checks if a path is a dynamic route
   */
  isDynamicRoute(pathPart) {
    return pathPart.includes('[') && pathPart.includes(']');
  }

  /**
   * Validates dynamic routes by checking if the pattern exists
   */
  validateDynamicRoute(pathPart) {
    // For now, assume dynamic routes are valid if the pattern exists
    // This could be enhanced to check the actual dynamic data
    const dynamicPattern = pathPart.replace(/\[.*?\]/g, '[*]');
    
    for (const lang of SUPPORTED_LANGUAGES) {
      const langDir = path.join(this.srcDir, lang);
      if (this.findDynamicPattern(langDir, pathPart)) {
        return true;
      }
    }
    
    return false;
  }

  /**
   * Recursively searches for dynamic route patterns
   */
  findDynamicPattern(dir, pattern) {
    if (!fs.existsSync(dir)) return false;
    
    const parts = pattern.split('/').filter(Boolean);
    let currentDir = dir;
    
    for (const part of parts) {
      if (part.startsWith('[') && part.endsWith(']')) {
        // Find any file/directory with square brackets
        const entries = fs.readdirSync(currentDir, { withFileTypes: true });
        const found = entries.find(entry => 
          entry.name.startsWith('[') && entry.name.includes(']')
        );
        
        if (!found) return false;
        currentDir = path.join(currentDir, found.name);
      } else {
        currentDir = path.join(currentDir, part);
        if (!fs.existsSync(currentDir)) return false;
      }
    }
    
    return true;
  }

  /**
   * Suggests corrections for broken links
   */
  suggestCorrection(href) {
    const corrections = new Map([
      ['/server/introduction/accounts-and-projects', '/guides/server/accounts-and-projects'],
      ['/server/introduction/integrations#git-platforms', '/guides/server/authentication'],
      ['/server/introduction/why-a-server', '/guides/tuist/about'],
      ['/guides/automate/continuous-integration', '/guides/integrations/continuous-integration'],
      ['/guides/features/automate/continuous-integration', '/guides/integrations/continuous-integration'],
      ['/guides/features/build/cache', '/guides/features/cache'],
      ['/guides/features/cache.html#supported-products', '/guides/features/cache#supported-products'],
      ['/guides/features/inspect/implicit-dependencies', '/guides/features/projects/inspect/implicit-dependencies'],
      ['/guides/start/new-project', '/guides/features/projects/adoption/new-project'],
      ['/guides/features/test', '/guides/features/selective-testing'],
      ['/guides/features/test/selective-testing', '/guides/features/selective-testing'],
      ['/guides/features/selective-testing/xcodebuild', '/guides/features/selective-testing/xcode-project'],
      ['/contributors/principles.html#default-to-conventions', '/contributors/principles#default-to-conventions']
    ]);
    
    return corrections.get(href) || null;
  }
}

/**
 * VitePress plugin to validate LocalizedLink components
 */
export function localizedLinkValidatorPlugin() {
  return {
    name: 'localized-link-validator',
    async buildStart() {
      // We'll run validation during buildEnd instead
    },
    async buildEnd({ outDir }) {
      const srcDir = path.join(path.dirname(outDir), 'docs');
      const validator = new LocalizedLinkValidator(srcDir);
      
      await validator.scanFiles();
      await validator.validateLinks();
    }
  };
}