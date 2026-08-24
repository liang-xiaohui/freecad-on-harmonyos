export interface FreeCadAcceptance {
  runAcceptance(outputDir: string, resourceManager: Object): Promise<string>;
  runJob(filesDir: string, requestJson: string, resourceManager: Object): Promise<string>;
  materializeFreecadRuntime(filesDir: string): void;
  materializeFreecadRuntimeAsync(filesDir: string): Promise<void>;
  prepareOpenGL(): void;
  setupFreecadEnv(filesDir: string, resourceManager: Object): void;
}

declare const freecad: FreeCadAcceptance;
export default freecad;
