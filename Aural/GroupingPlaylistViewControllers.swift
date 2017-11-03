/*
 View controller for playlist CRUD controls (adding/removing/reordering tracks and saving/loading to/from playlists)
 */

import Cocoa
import Foundation

class GroupingPlaylistViewController: NSViewController, AsyncMessageSubscriber, MessageSubscriber, ActionMessageSubscriber {
    
    @IBOutlet weak var playlistView: NSOutlineView!
    
    // Delegate that performs CRUD actions on the playlist
    private let playlist: PlaylistDelegateProtocol = ObjectGraph.getPlaylistDelegate()
    
    private let plAcc: PlaylistAccessorProtocol = ObjectGraph.getPlaylistAccessor()
    
    // Delegate that retrieves current playback info
    private let playbackInfo: PlaybackInfoDelegateProtocol = ObjectGraph.getPlaybackInfoDelegate()
    
    // A serial operation queue to help perform playlist update tasks serially, without overwhelming the main thread
    private let playlistUpdateQueue = OperationQueue()
    
    // Intended to be overriden by subclasses
    internal var groupType: GroupType {return .artist}
    internal var playlistType: PlaylistType {return .artists}
    
    override func viewDidLoad() {
        
        // Register self as a subscriber to various AsyncMessage notifications
        AsyncMessenger.subscribe(.trackAdded, subscriber: self, dispatchQueue: DispatchQueue.main)
        AsyncMessenger.subscribe(.trackInfoUpdated, subscriber: self, dispatchQueue: DispatchQueue.main)
        AsyncMessenger.subscribe(.tracksRemoved, subscriber: self, dispatchQueue: DispatchQueue.main)
        AsyncMessenger.subscribe(.tracksNotAdded, subscriber: self, dispatchQueue: DispatchQueue.main)
        
        // Register self as a subscriber to various synchronous message notifications
        SyncMessenger.subscribe(.trackAddedNotification, subscriber: self)
        SyncMessenger.subscribe(.trackChangedNotification, subscriber: self)
        SyncMessenger.subscribe(.removeTrackRequest, subscriber: self)
        SyncMessenger.subscribe(.searchResultSelectionRequest, subscriber: self)
        
        SyncMessenger.subscribe(actionType: .removeTracks, subscriber: self)
        SyncMessenger.subscribe(actionType: .clearPlaylist, subscriber: self)
        SyncMessenger.subscribe(actionType: .moveTracksUp, subscriber: self)
        SyncMessenger.subscribe(actionType: .moveTracksDown, subscriber: self)
        SyncMessenger.subscribe(actionType: .refresh, subscriber: self)
        SyncMessenger.subscribe(actionType: .scrollToTop, subscriber: self)
        SyncMessenger.subscribe(actionType: .scrollToBottom, subscriber: self)
        SyncMessenger.subscribe(actionType: .showPlayingTrack, subscriber: self)
        
        // Set up the serial operation queue for playlist view updates
        playlistUpdateQueue.maxConcurrentOperationCount = 1
        playlistUpdateQueue.underlyingQueue = DispatchQueue.main
        playlistUpdateQueue.qualityOfService = .background
    }
    
    func clearPlaylist() {
        playlist.clear()
        SyncMessenger.publishActionMessage(PlaylistActionMessage(.refresh, nil))
    }
    
    private func collectTracksAndGroups() -> (tracks: [Track], groups: [Group]) {
        
        let indexes = playlistView.selectedRowIndexes
        var tracks = [Track]()
        var groups = [Group]()
        
        indexes.forEach({
            
            let item = playlistView.item(atRow: $0)
            
            if let track = item as? Track {
                tracks.append(track)
            } else {
                // Group
                groups.append(item as! Group)
            }
        })
        
        return (tracks, groups)
    }
    
    func removeTracks() {
        
        let tracksAndGroups = collectTracksAndGroups()
        let tracks = tracksAndGroups.tracks
        let groups = tracksAndGroups.groups
        
        if (groups.count == plAcc.getNumberOfGroups(self.groupType)) {
            clearPlaylist()
            return
        }
        
        playlist.removeTracksAndGroups(tracks, groups, groupType)
    }
    
    func tracksRemoved(_ results: RemoveOperationResults) {
        
        let removals = results.groupingPlaylistResults[self.groupType]!
        var groupsToReload = [Group]()
        
        for removal in removals.results {
            
            if let trackRemoval = removal as? TracksRemovedResult {
                
//                print("\nRemoving tracks:", trackRemoval.trackIndexesInGroup.toArray(), "from group",  trackRemoval.parentGroup.name, "of type", trackRemoval.parentGroup.type, "at grp index:", trackRemoval.groupIndex)
                
                playlistView.removeItems(at: trackRemoval.trackIndexesInGroup, inParent: trackRemoval.parentGroup, withAnimation: .effectFade)
                
                groupsToReload.append(trackRemoval.parentGroup)
                
            } else {
                
                let groupRemoval = removal as! GroupRemovedResult
                
//                print("\nRemoving group:", groupRemoval.group.name, "of type", groupRemoval.group.type, "at index", groupRemoval.groupIndex)
                
                playlistView.removeItems(at: IndexSet(integer: groupRemoval.groupIndex), inParent: nil, withAnimation: .effectFade)
            }
        }
        
        // For all groups from which tracks were removed, reload them
        groupsToReload.forEach({
//            print("\nReloading group:", $0.name)
            playlistView.reloadItem($0, reloadChildren: false)
        })
    }
    
    // The "errorState" arg indicates whether the player is in an error state (i.e. the new track cannot be played back). If so, update the UI accordingly.
    private func trackChanged(_ oldTrack: IndexedTrack?, _ newTrack: IndexedTrack?, _ errorState: Bool = false) {

        if (oldTrack != nil) {
            playlistView.reloadItem(oldTrack!.track)
        }

        if (newTrack != nil) {
            playlistView.reloadItem(newTrack!.track)
        }
    }
    
    // Selects (and shows) a certain track within the playlist view
    private func selectTrack(_ track: GroupedTrack?) {
        
        if (playlistView.numberOfRows > 0) {
            
            if let _track = track?.track {
                
                // Need to expand the parent to make the child visible
                playlistView.expandItem(track?.group)
                
                let trackIndex = playlistView.row(forItem: _track)
                
                playlistView.selectRowIndexes(IndexSet(integer: trackIndex), byExtendingSelection: false)
                showPlaylistSelectedRow()
            }
        }
    }

    // Scrolls the playlist to show its selected row
    private func showPlaylistSelectedRow() {
        
        if (playlistView.numberOfRows > 0 && playlistView.selectedRow >= 0) {
            playlistView.scrollRowToVisible(playlistView.selectedRow)
        }
    }
    
    // Scrolls the playlist view to the very top
    func scrollToTop() {
        
        if (playlistView.numberOfRows > 0) {
            playlistView.scrollRowToVisible(0)
        }
    }
    
    // Scrolls the playlist view to the very bottom
    func scrollToBottom() {
        
        if (playlistView.numberOfRows > 0) {
            playlistView.scrollRowToVisible(playlistView.numberOfRows - 1)
        }
    }
    
    func refresh() {
        playlistView.reloadData()
    }
    
    func moveTracksUp() {
        
        let tracksAndGroups = collectTracksAndGroups()
        let tracks = tracksAndGroups.tracks
        let groups = tracksAndGroups.groups
        
        // Cannot move both tracks and groups
        if (tracks.count > 0 && groups.count > 0) {
            return
        }
        
        let results = playlist.moveTracksAndGroupsUp(tracks, groups, self.groupType)
        moveItems(results)
        
        var allItems: [GroupedPlaylistItem] = [GroupedPlaylistItem]()
        groups.forEach({allItems.append($0)})
        tracks.forEach({allItems.append($0)})
        selectAllItems(allItems)
        
        playlistView.scrollRowToVisible(playlistView.selectedRow)
    }
    
    private func moveItems(_ results: ItemMovedResults) {
        
        for result in results.results {
            
            if let trackMovedResult = result as? TrackMovedResult {
                
                playlistView.moveItem(at: trackMovedResult.oldTrackIndex, inParent: trackMovedResult.parentGroup, to: trackMovedResult.newTrackIndex, inParent: trackMovedResult.parentGroup)
                
            } else {
                
                let groupMovedResult = result as! GroupMovedResult
                playlistView.moveItem(at: groupMovedResult.oldGroupIndex, inParent: nil, to: groupMovedResult.newGroupIndex, inParent: nil)
            }
        }
    }
    
    private func selectAllItems(_ items: [GroupedPlaylistItem]) {
        var selIndexes = [Int]()
        items.forEach({selIndexes.append(playlistView.row(forItem: $0))})
        playlistView.selectRowIndexes(IndexSet(selIndexes), byExtendingSelection: false)
    }
    
    func moveTracksDown() {
        
        let tracksAndGroups = collectTracksAndGroups()
        let tracks = tracksAndGroups.tracks
        let groups = tracksAndGroups.groups
        
        // Cannot move both tracks and groups
        if (tracks.count > 0 && groups.count > 0) {
            return
        }
        
        let results = playlist.moveTracksAndGroupsDown(tracks, groups, self.groupType)
        moveItems(results)
        
        var allItems: [GroupedPlaylistItem] = [GroupedPlaylistItem]()
        groups.forEach({allItems.append($0)})
        tracks.forEach({allItems.append($0)})
        selectAllItems(allItems)
        
        playlistView.scrollRowToVisible(playlistView.selectedRow)
    }
    
    private func trackAdded(_ message: TrackAddedNotification) {
        
        let result = message.groupInfo[self.groupType]!
        
        if result.groupCreated {
            
            playlistView.insertItems(at: IndexSet(integer: result.track.groupIndex), inParent: nil, withAnimation: NSTableViewAnimationOptions.effectFade)
            
        } else {
            
            let group = result.track.group
            playlistView.insertItems(at: IndexSet(integer: result.track.trackIndex), inParent: group, withAnimation: .effectGap)
            playlistView.reloadItem(group)
        }
    }
    
    private func trackAdded(_ message: TrackAddedAsyncMessage) {
        
        let result = message.groupInfo[self.groupType]!
        
        if result.groupCreated {
            
            playlistView.insertItems(at: IndexSet(integer: result.track.groupIndex), inParent: nil, withAnimation: NSTableViewAnimationOptions.effectFade)
            
        } else {
        
            let group = result.track.group
            playlistView.insertItems(at: IndexSet(integer: result.track.trackIndex), inParent: group, withAnimation: .effectGap)
            playlistView.reloadItem(group)
        }
    }
    
    private func trackUpdated(_ message: TrackUpdatedAsyncMessage) {
        
        let track = message.groupInfo[self.groupType]!.track
        let group = message.groupInfo[self.groupType]!.group
        
        self.playlistView.reloadItem(group, reloadChildren: false)
        self.playlistView.reloadItem(track)
    }
    
    // Shows the currently playing track, within the playlist view
    func showPlayingTrack() {
        selectTrack(playbackInfo.getPlayingTrackGroupInfo(self.groupType))
    }
    
    private func showSearchResult(_ result: SearchResult) {
        selectTrack(result.location.groupInfo)
    }
    
    func consumeAsyncMessage(_ message: AsyncMessage) {
        
        if let msg = message as? TrackAddedAsyncMessage {
            trackAdded(msg)
            return
        }
        
        if let msg = message as? TrackUpdatedAsyncMessage {
            trackUpdated(msg)
            return
        }
        
        if let msg = message as? TracksRemovedAsyncMessage {
            tracksRemoved(msg.results)
            return
        }
    }
    
    func consumeNotification(_ notification: NotificationMessage) {
        
        if let msg = notification as? TrackAddedNotification {
            trackAdded(msg)
            return
        }
        
        if (notification is TrackChangedNotification) {
            
            let msg = notification as! TrackChangedNotification
            trackChanged(msg.oldTrack, msg.newTrack, msg.errorState)
            return
        }
    }
    
    func processRequest(_ request: RequestMessage) -> ResponseMessage {
        
        if PlaylistViewState.current == self.playlistType, let req = request as? SearchResultSelectionRequest {
            showSearchResult(req.searchResult)
            
            return EmptyResponse.instance
        }
        
        return EmptyResponse.instance
    }
    
    func consumeMessage(_ message: ActionMessage) {
        
        if let msg = message as? PlaylistActionMessage {
            
            if (msg.playlistType != nil && msg.playlistType != self.playlistType) {
                return
            }
            
            switch (msg.actionType) {
                
            case .refresh: refresh()
                
            case .removeTracks: removeTracks()
                
            case .showPlayingTrack: showPlayingTrack()
                
            case .moveTracksUp: moveTracksUp()
                
            case .moveTracksDown: moveTracksDown()
                
            case .scrollToTop: scrollToTop()
                
            case .scrollToBottom: scrollToBottom()
                
            default: return
                
            }
            
            return
        }
    }
}

extension IndexSet {
    
    func toArray() -> [Int] {
        return self.filter({$0 >= 0})
    }
}

class PlaylistArtistsViewController: GroupingPlaylistViewController {
    override internal var groupType: GroupType {return .artist}
    override internal var playlistType: PlaylistType {return .artists}
}

class PlaylistAlbumsViewController: GroupingPlaylistViewController {
    override internal var groupType: GroupType {return .album}
    override internal var playlistType: PlaylistType {return .albums}
}

class PlaylistGenresViewController: GroupingPlaylistViewController {
    override internal var groupType: GroupType {return .genre}
    override internal var playlistType: PlaylistType {return .genres}
}