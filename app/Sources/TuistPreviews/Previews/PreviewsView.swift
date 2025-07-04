import SwiftUI
import TuistErrorHandling
import TuistServer
import TuistNoora

public struct PreviewsView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @State var viewModel = PreviewsViewModel()
    @State private var searchText = ""
    
    public init() {}
    
    public var body: some View {
        List {
            // "Apps in Project" header as first row
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Apps in")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Menu {
                        ForEach(viewModel.projects, id: \.id) { project in
                            Button(project.fullName) {
                                Task {
                                    await viewModel.selectProject(project)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.selectedProject?.fullName ?? "Select Project")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(UIColor.systemGray4), lineWidth: 0.5)
                        )
                    }
                    
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            
            ForEach(viewModel.previews) { preview in
                PreviewRowView(preview: preview)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .onAppear {
                        if preview.id == viewModel.previews.last?.id {
                            Task {
                                await viewModel.loadMorePreviews()
                            }
                        }
                    }
            }
            
            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .onAppear {
            errorHandling.fireAndHandleError {
                try await viewModel.onAppear()
            }
        }
        .navigationTitle("Previews")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

struct PreviewRowView: View {
    let preview: TuistServer.Preview
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsyncImage(url: preview.iconURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image("AppIconPlaceholder")
                        .resizable()
                        .scaledToFit()
                }
                .cornerRadius(Noora.CornerRadius.medium)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                .frame(width: 48, height: 48)
                
                // App info
                VStack(alignment: .leading, spacing: 4) {
                    // Top metadata row
                    HStack(spacing: 8) {
                        if let commitSHA = preview.gitCommitSHA {
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(String(commitSHA.prefix(7)))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // App name
                    Text(preview.displayName ?? "App")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Bottom metadata row
                    HStack(spacing: 8) {
                        // Time ago
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("22h ago")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        // Branch
                        if let branch = preview.gitBranch {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.branch")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(branch)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
                
                // Run button
                Button(action: {
                    let url =
                    URL(string: "itms-services://?action=download-manifest&url=\(preview.url.absoluteString)/manifest.plist")!
                    UIApplication.shared.open(url)
                }) {
                    Text("Run")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.435, green: 0.173, blue: 1.0))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.435, green: 0.173, blue: 1.0, opacity: 0.15))
                        .cornerRadius(20)
                }
            }
            .padding(.vertical, 12)
            
            // Divider
            Rectangle()
                .fill(Color(UIColor.systemGray5))
                .frame(height: 1)
        }
    }
}
