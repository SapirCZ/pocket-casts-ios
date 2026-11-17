import Foundation
import PocketCastsDataModel
import PocketCastsUtils

public extension ApiServerHandler {
    func retrieveCustomFilesTask() {
        let retrieveTask = RetrieveCustomFilesTask()
        apiQueue.addOperation(retrieveTask)
    }

    func uploadFileRequest(episode: UserEpisode, completion: @escaping (URL?) -> Void) {
        guard DataManager.sharedManager.canSyncUserEpisode(uuid: episode.uuid) else { completion(nil); return }
        let uploadOperation = UploadFileRequestTask(episode: episode)
        uploadOperation.completion = completion
        apiQueue.addOperation(uploadOperation)
    }

    func uploadImageRequest(episode: UserEpisode, completion: @escaping (URL?) -> Void) {
        guard DataManager.sharedManager.canSyncUserEpisode(uuid: episode.uuid) else { completion(nil); return }
        let uploadOperation = UploadImageRequestTask(episode: episode)
        uploadOperation.completion = completion
        apiQueue.addOperation(uploadOperation)
    }

    func uploadFileDelete(episode: UserEpisode, completion: @escaping (Bool?) -> Void) {
        guard DataManager.sharedManager.canSyncUserEpisode(uuid: episode.uuid) else { completion(nil); return }
        let deleteOperation = UploadFileDeleteTask(episode: episode)
        deleteOperation.completion = completion
        apiQueue.addOperation(deleteOperation)
    }

    func uploadFilePlayRequest(episode: UserEpisode, completion: @escaping (URL?) -> Void) {
        guard DataManager.sharedManager.canSyncUserEpisode(uuid: episode.uuid) else { completion(nil); return }
        let requestOperation = UploadFilePlayRequestTask(episode: episode)
        requestOperation.completion = completion
        apiQueue.addOperation(requestOperation)
    }

    func uploadFilesUpdateRequest(episodes: [UserEpisode], completion: @escaping (Int) -> Void) {
        let episodes = episodes.filter { DataManager.sharedManager.canSyncUserEpisode(uuid: $0.uuid) }
        guard !episodes.isEmpty else { completion(0); return }
        let saveOperation = UploadFilesUpdateTask(episodes: episodes)
        saveOperation.completion = completion
        apiQueue.addOperation(saveOperation)
    }

    func uploadSingleFileUpdateRequest(episode: UserEpisode, completion: @escaping (Int) -> Void) {
        uploadFilesUpdateRequest(episodes: [episode], completion: completion)
    }

    func uploadFilesUpdateStatusRequest(episode: UserEpisode) {
        guard DataManager.sharedManager.canSyncUserEpisode(uuid: episode.uuid) else { return }
        let statusOperation = RetrieveFileUploadStatusTask(episode: episode)
        apiQueue.addOperation(statusOperation)
    }

    func uploadImageDelete(episode: UserEpisode, completion: @escaping (Bool?) -> Void) {
        guard DataManager.sharedManager.canSyncUserEpisode(uuid: episode.uuid) else { completion(nil); return }
        let deleteOperation = UploadImageDeleteTask(episode: episode)
        deleteOperation.completion = completion
        apiQueue.addOperation(deleteOperation)
    }

    func uploadFileUsageRequest() {
        let fileUsageOperation = RetrieveFileUsageTask()
        apiQueue.addOperation(fileUsageOperation)
    }
}
